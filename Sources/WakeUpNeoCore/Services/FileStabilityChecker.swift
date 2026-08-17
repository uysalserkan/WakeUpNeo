import Foundation

/// Snapshot representing a file's observed size and modification metadata.
public struct FileMetadata: Equatable, Sendable {
    public let exists: Bool
    public let size: Int64
    public let modificationDate: Date?
    
    public init(exists: Bool, size: Int64, modificationDate: Date?) {
        self.exists = exists
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// Evaluates file size and modification timestamp stability over a configurable duration window.
public final class FileStabilityChecker: @unchecked Sendable {
    
    private struct FileSnapshot: Equatable {
        let size: Int64
        let modificationDate: Date
        let firstObservedAt: Date
        let lastObservedAt: Date
    }
    
    private let lock = NSLock()
    public let stabilizationDuration: TimeInterval
    private var lastSnapshot: FileSnapshot?
    private var isCompleted: Bool = false
    
    public init(stabilizationDuration: TimeInterval = 2.0) {
        self.stabilizationDuration = max(0.1, stabilizationDuration)
    }
    
    /// Reads metadata from a target file or directory package.
    public static func readMetadata(at url: URL, fileManager: FileManager = .default) -> FileMetadata {
        let path = url.path(percentEncoded: false)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            return FileMetadata(exists: false, size: 0, modificationDate: nil)
        }
        
        if isDir.boolValue {
            return readDirectoryMetadata(at: url, fileManager: fileManager)
        }
        
        do {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = attrs[.modificationDate] as? Date
            return FileMetadata(exists: true, size: size, modificationDate: modDate)
        } catch {
            return FileMetadata(exists: false, size: 0, modificationDate: nil)
        }
    }
    
    private static func readDirectoryMetadata(at url: URL, fileManager: FileManager) -> FileMetadata {
        let path = url.path(percentEncoded: false)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else {
            let attrs = try? fileManager.attributesOfItem(atPath: path)
            let modDate = attrs?[.modificationDate] as? Date
            return FileMetadata(exists: true, size: 0, modificationDate: modDate)
        }
        
        var totalSize: Int64 = 0
        var latestModDate: Date? = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) else { continue }
            if values.isRegularFile == true {
                totalSize += Int64(values.fileSize ?? 0)
            }
            if let mod = values.contentModificationDate {
                if latestModDate == nil || mod > latestModDate! {
                    latestModDate = mod
                }
            }
        }
        
        return FileMetadata(exists: true, size: totalSize, modificationDate: latestModDate)
    }
    
    /// Evaluates target file stability against current observations and configured window.
    /// - Parameters:
    ///   - url: Target file path to check.
    ///   - now: Current timestamp (injectable for deterministic testing).
    /// - Returns: `FileWatcherTargetFileState` indicating existence, stabilizing status, and current size.
    public func evaluate(at url: URL, now: Date = Date.now) -> FileWatcherTargetFileState {
        lock.withLock {
            let meta = Self.readMetadata(at: url)
            guard meta.exists else {
                lastSnapshot = nil
                isCompleted = false
                return FileWatcherTargetFileState(
                    targetPath: url,
                    exists: false,
                    isStabilizing: false,
                    currentSize: 0
                )
            }
            
            let currentSize = meta.size
            let currentModDate = meta.modificationDate ?? now
            let timeSinceLastModification = now.timeIntervalSince(currentModDate)
            
            if let snapshot = lastSnapshot {
                if snapshot.size != currentSize || snapshot.modificationDate != currentModDate {
                    // File is actively changing / being written
                    lastSnapshot = FileSnapshot(
                        size: currentSize,
                        modificationDate: currentModDate,
                        firstObservedAt: now,
                        lastObservedAt: now
                    )
                    isCompleted = false
                    return FileWatcherTargetFileState(
                        targetPath: url,
                        exists: true,
                        isStabilizing: true,
                        currentSize: currentSize
                    )
                } else {
                    // File metadata unchanged since last observation
                    let stableDuration = now.timeIntervalSince(snapshot.firstObservedAt)
                    if stableDuration >= stabilizationDuration {
                        isCompleted = true
                        return FileWatcherTargetFileState(
                            targetPath: url,
                            exists: true,
                            isStabilizing: false,
                            currentSize: currentSize
                        )
                    } else {
                        return FileWatcherTargetFileState(
                            targetPath: url,
                            exists: true,
                            isStabilizing: true,
                            currentSize: currentSize
                        )
                    }
                }
            } else {
                // First observation
                if timeSinceLastModification >= stabilizationDuration {
                    // Fast-path: file finished writing prior to this observation
                    lastSnapshot = FileSnapshot(
                        size: currentSize,
                        modificationDate: currentModDate,
                        firstObservedAt: currentModDate,
                        lastObservedAt: now
                    )
                    isCompleted = true
                    return FileWatcherTargetFileState(
                        targetPath: url,
                        exists: true,
                        isStabilizing: false,
                        currentSize: currentSize
                    )
                } else {
                    lastSnapshot = FileSnapshot(
                        size: currentSize,
                        modificationDate: currentModDate,
                        firstObservedAt: now,
                        lastObservedAt: now
                    )
                    isCompleted = false
                    return FileWatcherTargetFileState(
                        targetPath: url,
                        exists: true,
                        isStabilizing: true,
                        currentSize: currentSize
                    )
                }
            }
        }
    }
    
    /// Resets stability history.
    public func reset() {
        lock.withLock {
            lastSnapshot = nil
            isCompleted = false
        }
    }
}
