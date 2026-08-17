import Foundation
@testable import WakeUpNeoCore

/// Mock test double for `FileWatchingService` enabling isolated unit testing of downstream coordinators.
public final class MockFileWatchingService: FileWatchingService, @unchecked Sendable {
    private let lock = NSLock()
    
    public private(set) var isWatching: Bool = false
    public private(set) var watchDownloadsCallCount = 0
    public private(set) var waitForFileCallCount = 0
    public private(set) var stopCallCount = 0
    
    public private(set) var lastWatchedDirectory: URL?
    public private(set) var lastTemporaryExtensions: Set<String>?
    public private(set) var lastTargetPath: URL?
    public private(set) var lastStabilizationDuration: TimeInterval?
    
    public var shouldThrowOnWatch: Error?
    
    private var downloadUpdateHandler: (@Sendable (FileWatcherDownloadState) -> Void)?
    private var downloadCompleteHandler: (@Sendable () -> Void)?
    private var targetUpdateHandler: (@Sendable (FileWatcherTargetFileState) -> Void)?
    private var targetCompleteHandler: (@Sendable () -> Void)?
    private var errorHandler: (@Sendable (Error) -> Void)?
    
    public init() {}
    
    public func watchDownloads(
        in directory: URL,
        temporaryExtensions: Set<String>,
        onUpdate: @escaping @Sendable (FileWatcherDownloadState) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        lock.withLock {
            watchDownloadsCallCount += 1
            lastWatchedDirectory = directory
            lastTemporaryExtensions = temporaryExtensions
            downloadUpdateHandler = onUpdate
            downloadCompleteHandler = onComplete
            errorHandler = onError
        }
        
        if let error = shouldThrowOnWatch {
            throw error
        }
        
        lock.withLock {
            isWatching = true
        }
    }
    
    public func waitForFile(
        at targetPath: URL,
        stabilizationDuration: TimeInterval,
        onUpdate: @escaping @Sendable (FileWatcherTargetFileState) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        lock.withLock {
            waitForFileCallCount += 1
            lastTargetPath = targetPath
            lastStabilizationDuration = stabilizationDuration
            targetUpdateHandler = onUpdate
            targetCompleteHandler = onComplete
            errorHandler = onError
        }
        
        if let error = shouldThrowOnWatch {
            throw error
        }
        
        lock.withLock {
            isWatching = true
        }
    }
    
    public func stop() {
        lock.withLock {
            stopCallCount += 1
            isWatching = false
            downloadUpdateHandler = nil
            downloadCompleteHandler = nil
            targetUpdateHandler = nil
            targetCompleteHandler = nil
            errorHandler = nil
        }
    }
    
    public func simulateDownloadUpdate(_ state: FileWatcherDownloadState) {
        let handler = lock.withLock { downloadUpdateHandler }
        handler?(state)
    }
    
    public func simulateDownloadComplete() {
        let handler = lock.withLock { downloadCompleteHandler }
        handler?()
    }
    
    public func simulateTargetFileUpdate(_ state: FileWatcherTargetFileState) {
        let handler = lock.withLock { targetUpdateHandler }
        handler?(state)
    }
    
    public func simulateTargetFileComplete() {
        let handler = lock.withLock { targetCompleteHandler }
        handler?()
    }
    
    public func simulateError(_ error: Error) {
        let handler = lock.withLock { errorHandler }
        handler?(error)
    }
    
    public func reset() {
        lock.withLock {
            isWatching = false
            watchDownloadsCallCount = 0
            waitForFileCallCount = 0
            stopCallCount = 0
            lastWatchedDirectory = nil
            lastTemporaryExtensions = nil
            lastTargetPath = nil
            lastStabilizationDuration = nil
            shouldThrowOnWatch = nil
            downloadUpdateHandler = nil
            downloadCompleteHandler = nil
            targetUpdateHandler = nil
            targetCompleteHandler = nil
            errorHandler = nil
        }
    }
}
