import Foundation

/// RAII helper for creating isolated temporary directories for filesystem unit tests.
public final class TestTempDirectory: @unchecked Sendable {
    public let url: URL
    public var path: String { url.path(percentEncoded: false) }
    private let fileManager = FileManager.default
    
    public init(prefix: String = "WakeUpNeoTests") throws {
        let uniqueName = "\(prefix)-\(UUID().uuidString)"
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(uniqueName, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.url = tempDir
    }
    
    @discardableResult
    public func createFile(named name: String, contents: Data = Data()) throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try contents.write(to: fileURL)
        return fileURL
    }
    
    @discardableResult
    public func createFile(named name: String, text: String) throws -> URL {
        try createFile(named: name, contents: Data(text.utf8))
    }
    
    @discardableResult
    public func createDirectory(named name: String) throws -> URL {
        let dirURL = url.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL
    }
    
    @discardableResult
    public func createDownloadPackage(named name: String, files: [String: Data] = [:]) throws -> URL {
        let packageURL = try createDirectory(named: name)
        for (fileName, data) in files {
            let fileURL = packageURL.appendingPathComponent(fileName)
            let parentDir = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try data.write(to: fileURL)
        }
        return packageURL
    }
    
    public func append(data: Data, toFileNamed name: String) throws {
        let fileURL = url.appendingPathComponent(name)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
    
    public func removeFile(named name: String) throws {
        let fileURL = url.appendingPathComponent(name)
        if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    public func renameFile(from oldName: String, to newName: String) throws {
        let src = url.appendingPathComponent(oldName)
        let dst = url.appendingPathComponent(newName)
        try fileManager.moveItem(at: src, to: dst)
    }
    
    public func cleanup() {
        if fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(at: url)
        }
    }
    
    deinit {
        cleanup()
    }
}
