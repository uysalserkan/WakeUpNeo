import Foundation
import OSLog

private let logger = Logger(subsystem: "com.wakeupneo.app", category: "DefaultFileWatcherService")

/// Battery-efficient, event-driven file monitoring service using `DispatchSourceFileSystemObject`
/// with `O_EVTONLY` on directories and an adaptive fallback timer.
public final class DefaultFileWatcherService: FileWatchingService, @unchecked Sendable {
    
    private enum MonitoringMode {
        case none
        case downloads(directory: URL, extensions: Set<String>)
        case targetFile(target: URL, checker: FileStabilityChecker)
    }
    
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.wakeupneo.filewatcher", qos: .utility)
    
    private var mode: MonitoringMode = .none
    private var fileDescriptor: Int32?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: DispatchSourceTimer?
    private var debounceWorkItem: DispatchWorkItem?
    
    private var hasSeenActiveDownloads = false
    private var lastEmittedDownloads: [String]?
    private var lastEmittedTargetState: FileWatcherTargetFileState?
    
    private var downloadUpdateCallback: (@Sendable (FileWatcherDownloadState) -> Void)?
    private var downloadCompleteCallback: (@Sendable () -> Void)?
    private var targetUpdateCallback: (@Sendable (FileWatcherTargetFileState) -> Void)?
    private var targetCompleteCallback: (@Sendable () -> Void)?
    private var errorCallback: (@Sendable (Error) -> Void)?
    
    public var isWatching: Bool {
        lock.withLock {
            if case .none = mode { return false }
            return true
        }
    }
    
    public init() {}
    
    // MARK: - Watch Downloads
    
    public func watchDownloads(
        in directory: URL,
        temporaryExtensions: Set<String>,
        onUpdate: @escaping @Sendable (FileWatcherDownloadState) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        try lock.withLock {
            guard case .none = mode else {
                throw FileWatcherError.alreadyWatching
            }
            
            let path = directory.path(percentEncoded: false)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                throw FileWatcherError.directoryNotFound(directory)
            }
            
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else {
                let err = errno
                logger.error("Failed to open descriptor for '\(path)': errno \(err)")
                throw FileWatcherError.unableToOpenDescriptor(err)
            }
            
            self.fileDescriptor = fd
            self.downloadUpdateCallback = onUpdate
            self.downloadCompleteCallback = onComplete
            self.errorCallback = onError
            self.mode = .downloads(directory: directory, extensions: temporaryExtensions)
            self.hasSeenActiveDownloads = false
            self.lastEmittedDownloads = nil
            
            // Set up DispatchSource
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
                queue: queue
            )
            
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let data = source.data
                if data.contains(.delete) || data.contains(.revoke) {
                    self.handleWatchedDirectoryDeleted(directory)
                } else {
                    self.scheduleDebouncedScan()
                }
            }
            
            source.setCancelHandler {
                close(fd)
            }
            
            self.dispatchSource = source
            source.resume()
            
            // Set up Fallback Timer (ticks every 1.5 seconds)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1.5, repeating: 1.5, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                self?.performScan()
            }
            self.fallbackTimer = timer
            timer.resume()
        }
        
        // Initial scan executed immediately on serial queue
        queue.async { [weak self] in
            self?.performScan()
        }
    }
    
    // MARK: - Wait For File
    
    public func waitForFile(
        at targetPath: URL,
        stabilizationDuration: TimeInterval,
        onUpdate: @escaping @Sendable (FileWatcherTargetFileState) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        try lock.withLock {
            guard case .none = mode else {
                throw FileWatcherError.alreadyWatching
            }
            
            let parentDir = targetPath.deletingLastPathComponent()
            let parentPath = parentDir.path(percentEncoded: false)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parentPath, isDirectory: &isDir), isDir.boolValue else {
                throw FileWatcherError.directoryNotFound(parentDir)
            }
            
            let fd = open(parentPath, O_EVTONLY)
            guard fd >= 0 else {
                let err = errno
                logger.error("Failed to open descriptor for parent '\(parentPath)': errno \(err)")
                throw FileWatcherError.unableToOpenDescriptor(err)
            }
            
            let checker = FileStabilityChecker(stabilizationDuration: stabilizationDuration)
            self.fileDescriptor = fd
            self.targetUpdateCallback = onUpdate
            self.targetCompleteCallback = onComplete
            self.errorCallback = onError
            self.mode = .targetFile(target: targetPath, checker: checker)
            self.lastEmittedTargetState = nil
            
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend, .attrib, .link, .revoke],
                queue: queue
            )
            
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let data = source.data
                if data.contains(.delete) || data.contains(.revoke) {
                    self.handleWatchedDirectoryDeleted(parentDir)
                } else {
                    self.scheduleDebouncedScan()
                }
            }
            
            source.setCancelHandler {
                close(fd)
            }
            
            self.dispatchSource = source
            source.resume()
            
            // Fallback Timer for stability duration ticks (every 0.5s)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in
                self?.performScan()
            }
            self.fallbackTimer = timer
            timer.resume()
        }
        
        queue.async { [weak self] in
            self?.performScan()
        }
    }
    
    // MARK: - Stop
    
    public func stop() {
        lock.withLock {
            tearDownInternal()
        }
    }
    
    private func tearDownInternal() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        
        fallbackTimer?.cancel()
        fallbackTimer = nil
        
        if let source = dispatchSource {
            source.cancel()
            dispatchSource = nil
        }
        fileDescriptor = nil
        
        mode = .none
        hasSeenActiveDownloads = false
        lastEmittedDownloads = nil
        lastEmittedTargetState = nil
        
        downloadUpdateCallback = nil
        downloadCompleteCallback = nil
        targetUpdateCallback = nil
        targetCompleteCallback = nil
        errorCallback = nil
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Internal Scanning
    
    private func scheduleDebouncedScan() {
        lock.withLock {
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.performScan()
            }
            debounceWorkItem = workItem
            queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: workItem)
        }
    }
    
    private func performScan() {
        let (currentMode, onDownloadUpdate, onDownloadComplete, onTargetUpdate, onTargetComplete, onError) = lock.withLock {
            (
                self.mode,
                self.downloadUpdateCallback,
                self.downloadCompleteCallback,
                self.targetUpdateCallback,
                self.targetCompleteCallback,
                self.errorCallback
            )
        }
        
        switch currentMode {
        case .none:
            break
            
        case .downloads(let directory, let extensions):
            let path = directory.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else {
                onError?(FileWatcherError.directoryNotFound(directory))
                stop()
                return
            }
            
            let active = DownloadPatternMatcher.activeDownloads(in: directory, temporaryExtensions: extensions)
            let (shouldUpdate, shouldComplete) = lock.withLock { () -> (Bool, Bool) in
                // Guard against mode changes while scanning
                guard case .downloads = self.mode else { return (false, false) }
                
                if !active.isEmpty {
                    self.hasSeenActiveDownloads = true
                }
                
                let changed = (self.lastEmittedDownloads != active)
                self.lastEmittedDownloads = active
                
                let complete = self.hasSeenActiveDownloads && active.isEmpty
                return (changed, complete)
            }
            
            if shouldUpdate {
                onDownloadUpdate?(FileWatcherDownloadState(directory: directory, activeDownloads: active))
            }
            
            if shouldComplete {
                stop()
                onDownloadComplete?()
            }
            
        case .targetFile(let targetPath, let checker):
            let state = checker.evaluate(at: targetPath)
            let (shouldUpdate, shouldComplete) = lock.withLock { () -> (Bool, Bool) in
                // Guard against mode changes while scanning
                guard case .targetFile = self.mode else { return (false, false) }
                
                let changed = (self.lastEmittedTargetState != state)
                self.lastEmittedTargetState = state
                let complete = state.exists && !state.isStabilizing
                return (changed, complete)
            }
            
            if shouldUpdate {
                onTargetUpdate?(state)
            }
            
            if shouldComplete {
                stop()
                onTargetComplete?()
            }
        }
    }
    
    private func handleWatchedDirectoryDeleted(_ directory: URL) {
        let onError = lock.withLock { self.errorCallback }
        onError?(FileWatcherError.directoryNotFound(directory))
        stop()
    }
}
