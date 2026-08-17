import AppKit
import Foundation
import UniformTypeIdentifiers
import WakeUpNeoCore

// MARK: - FilePickerHelper

/// MainActor-isolated helper for presenting native macOS `NSOpenPanel` file and folder pickers.
///
/// Designed specifically for menu bar and popover environments (`LSUIElement` apps),
/// ensuring panels are activated to the foreground with appropriate window levels and defaults.
@MainActor
public enum FilePickerHelper {

    // MARK: - Panel Configuration Factory (Testable & Headless-Safe)

    /// Creates and configures an `NSOpenPanel` configured for directory / folder selection.
    public static func createFolderOpenPanel(
        initialURL: URL? = nil,
        prompt: String = "Choose",
        title: String = "Select Downloads Folder",
        message: String = "Choose a folder to watch for active downloads"
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true
        panel.prompt = prompt
        panel.title = title
        panel.message = message
        panel.directoryURL = initialURL ?? AppSettings.defaultDownloadsURL
        panel.level = .floating
        return panel
    }

    /// Creates and configures an `NSOpenPanel` configured for target file selection.
    public static func createFileOpenPanel(
        initialURL: URL? = nil,
        allowedContentTypes: [UTType]? = nil,
        prompt: String = "Watch",
        title: String = "Select File to Watch",
        message: String = "Select a file to wait for completion before allowing sleep."
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = prompt
        panel.title = title
        panel.message = message
        panel.directoryURL = initialURL ?? AppSettings.defaultDownloadsURL
        if let types = allowedContentTypes, !types.isEmpty {
            panel.allowedContentTypes = types
        }
        panel.level = .floating
        return panel
    }

    // MARK: - Folder Selection

    /// Prompts the user synchronously to select a folder using `runModal()`.
    ///
    /// - Parameter initialURL: Optional initial directory. Defaults to standard Downloads directory.
    /// - Returns: Selected folder URL, or `nil` if cancelled.
    public static func selectFolder(initialURL: URL? = nil) -> URL? {
        let panel = createFolderOpenPanel(initialURL: initialURL)
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    /// Prompts the user asynchronously to select a folder using `begin(completionHandler:)`.
    public static func selectFolder(
        initialURL: URL? = nil,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = createFolderOpenPanel(initialURL: initialURL)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    /// Modern async wrapper for folder selection.
    @discardableResult
    public static func selectFolder(initialURL: URL? = nil) async -> URL? {
        await withCheckedContinuation { continuation in
            selectFolder(initialURL: initialURL) { url in
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: - Target File Selection

    /// Prompts the user synchronously to select a target file using `runModal()`.
    ///
    /// - Parameter initialURL: Optional initial directory or file path. Defaults to standard Downloads directory.
    /// - Returns: Selected file URL, or `nil` if cancelled.
    public static func selectTargetFile(initialURL: URL? = nil) -> URL? {
        let panel = createFileOpenPanel(initialURL: initialURL)
        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    /// Prompts the user asynchronously to select a target file using `begin(completionHandler:)`.
    public static func selectTargetFile(
        initialURL: URL? = nil,
        allowedContentTypes: [UTType]? = nil,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = createFileOpenPanel(initialURL: initialURL, allowedContentTypes: allowedContentTypes)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }

    /// Modern async wrapper for target file selection.
    @discardableResult
    public static func selectTargetFile(
        initialURL: URL? = nil,
        allowedContentTypes: [UTType]? = nil
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            selectTargetFile(initialURL: initialURL, allowedContentTypes: allowedContentTypes) { url in
                continuation.resume(returning: url)
            }
        }
    }
}
