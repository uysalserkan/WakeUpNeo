import Foundation

/// Pure utility for matching and classifying temporary download files across major browsers and download managers.
public enum DownloadPatternMatcher: Sendable {
    
    /// Default set of normalized temporary download extensions (without leading dot, lowercase).
    public static let defaultExtensions: Set<String> = [
        "crdownload", // Chrome, Chromium, Microsoft Edge, Brave, Opera, Vivaldi
        "download",   // Apple Safari (file or directory package)
        "part",       // Mozilla Firefox, Tor Browser, aria2, curl partial
        "tmp",        // Generic temporary download
        "partial",    // Generic / wget / Edge legacy
        "aria2",      // aria2 download manager
        "!ut",        // uTorrent / BitTorrent partial
        "utpart"      // BitTorrent / Transmission partial
    ]
    
    /// Normalizes an extension string by trimming whitespace, stripping leading dots, and lowercasing.
    public static func normalizeExtension(_ ext: String) -> String {
        var cleaned = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned
    }
    
    /// Merges default extensions with optional custom extensions, all normalized.
    public static func effectiveExtensions(customExtensions: Set<String>? = nil) -> Set<String> {
        guard let custom = customExtensions, !custom.isEmpty else {
            return defaultExtensions
        }
        let normalizedCustom = Set(custom.map(normalizeExtension).filter { !$0.isEmpty })
        return defaultExtensions.union(normalizedCustom)
    }
    
    /// Evaluates whether a filename or path represents an active temporary download.
    /// - Parameters:
    ///   - fileName: The file name or path component to evaluate.
    ///   - customExtensions: Optional additional temporary extensions.
    /// - Returns: `true` if the filename matches temporary download patterns; otherwise `false`.
    public static func isTemporaryDownload(fileName: String, customExtensions: Set<String>? = nil) -> Bool {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        // Strip trailing slash if directory-like path
        let cleaned = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let url = URL(fileURLWithPath: cleaned)
        let ext = url.pathExtension.lowercased()
        
        let targetExtensions = effectiveExtensions(customExtensions: customExtensions)
        
        // 1. Direct path extension match (e.g. "archive.tar.gz.crdownload" -> "crdownload")
        if !ext.isEmpty && targetExtensions.contains(ext) {
            return true
        }
        
        // 2. Suffix check for files without stem or packages (e.g. ".crdownload" or "bundle.download")
        let lowercasedName = url.lastPathComponent.lowercased()
        for targetExt in targetExtensions {
            if lowercasedName.hasSuffix("." + targetExt) {
                return true
            }
        }
        
        return false
    }
    
    /// Evaluates whether a URL represents an active temporary download.
    public static func isTemporaryDownload(url: URL, customExtensions: Set<String>? = nil) -> Bool {
        isTemporaryDownload(fileName: url.lastPathComponent, customExtensions: customExtensions)
    }
    
    /// Scans a directory and returns a sorted list of all active temporary download file/folder names.
    /// - Parameters:
    ///   - directory: The directory to scan.
    ///   - temporaryExtensions: Optional set of custom temporary extensions.
    ///   - fileManager: The `FileManager` instance to use (defaults to `.default`).
    /// - Returns: A deterministic, alphabetically sorted array of temporary download file names.
    public static func activeDownloads(
        in directory: URL,
        temporaryExtensions: Set<String>? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: []
        ) else {
            return []
        }
        
        var results = [String]()
        for item in contents {
            let name = item.lastPathComponent
            if name == "." || name == ".." || name == ".DS_Store" || name == ".localized" {
                continue
            }
            if isTemporaryDownload(url: item, customExtensions: temporaryExtensions) {
                results.append(name)
            }
        }
        return results.sorted()
    }
}
