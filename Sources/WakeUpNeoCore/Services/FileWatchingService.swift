import Foundation

/// Snapshot of the download directory state.
public struct FileWatcherDownloadState: Equatable, Sendable {
    public let directory: URL
    public let activeDownloads: [String]
    public var hasActiveDownloads: Bool { !activeDownloads.isEmpty }
    
    public init(directory: URL, activeDownloads: [String]) {
        self.directory = directory
        self.activeDownloads = activeDownloads
    }
}

/// Snapshot of the target file existence and stabilization state.
public struct FileWatcherTargetFileState: Equatable, Sendable {
    public let targetPath: URL
    public let exists: Bool
    public let isStabilizing: Bool
    public let currentSize: Int64
    
    public init(targetPath: URL, exists: Bool, isStabilizing: Bool, currentSize: Int64) {
        self.targetPath = targetPath
        self.exists = exists
        self.isStabilizing = isStabilizing
        self.currentSize = currentSize
    }
}

/// Errors raised by file watching operations.
public enum FileWatcherError: Error, LocalizedError, Sendable {
    case directoryNotFound(URL)
    case unreadablePath(URL)
    case alreadyWatching
    case unableToOpenDescriptor(Int32)
    
    public var errorDescription: String? {
        switch self {
        case .directoryNotFound(let url):
            return "The directory at '\(url.path(percentEncoded: false))' does not exist."
        case .unreadablePath(let url):
            return "Cannot read file or directory at '\(url.path(percentEncoded: false))'."
        case .alreadyWatching:
            return "File watching is already active."
        case .unableToOpenDescriptor(let code):
            return "Unable to open file descriptor for monitoring (error code: \(code))."
        }
    }
}

/// Protocol contract for file and download monitoring services.
public protocol FileWatchingService: Sendable {
    var isWatching: Bool { get }
    
    func watchDownloads(
        in directory: URL,
        temporaryExtensions: Set<String>,
        onUpdate: @escaping @Sendable (FileWatcherDownloadState) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws
    
    func waitForFile(
        at targetPath: URL,
        stabilizationDuration: TimeInterval,
        onUpdate: @escaping @Sendable (FileWatcherTargetFileState) -> Void,
        onComplete: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws
    
    func stop()
}
