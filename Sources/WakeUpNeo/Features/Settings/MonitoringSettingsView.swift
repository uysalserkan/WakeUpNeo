import SwiftUI
import WakeUpNeoCore

// MARK: - MonitoringSettingsView

/// The Monitoring tab in Settings: default downloads folder, file stabilization duration,
/// custom temporary file extensions, and smart watcher notification preferences.
struct MonitoringSettingsView: View {

    @AppStorage(AppSettingsKeys.watchedDownloadsPath)
    private var watchedDownloadsPath: String = AppSettings.defaultDownloadsURL.path(percentEncoded: false)

    @AppStorage(AppSettingsKeys.fileStabilizationDuration)
    private var fileStabilizationDuration: Double = 2.0

    @AppStorage(AppSettingsKeys.customTemporaryExtensions)
    private var customTemporaryExtensions: String = ""

    @AppStorage(AppSettingsKeys.notifyOnDownloadsComplete)
    private var notifyOnDownloadsComplete: Bool = true

    @AppStorage(AppSettingsKeys.notifyOnFileDetected)
    private var notifyOnFileDetected: Bool = true

    private var isCustomPath: Bool {
        watchedDownloadsPath != AppSettings.defaultDownloadsURL.path(percentEncoded: false)
    }

    var body: some View {
        Form {
            // MARK: Downloads Folder Section
            Section("Downloads Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text(displayPath(watchedDownloadsPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(watchedDownloadsPath)
                            .accessibilityLabel("Current watched folder: \(displayPath(watchedDownloadsPath))")

                        Spacer()

                        Button("Choose…") {
                            chooseFolder()
                        }
                        .accessibilityLabel("Choose downloads folder")
                        .accessibilityHint("Opens a dialog to select a folder for download monitoring")
                    }

                    if isCustomPath {
                        Button("Reset to Default Downloads Folder") {
                            watchedDownloadsPath = AppSettings.defaultDownloadsURL.path(percentEncoded: false)
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                        .accessibilityLabel("Reset watched folder to standard Downloads directory")
                    }
                }

                Text("WakeUpNeo monitors this folder for active downloads and keeps your Mac awake until all downloads complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Target File Stabilization Section
            Section("Target File Stabilization") {
                Stepper(
                    value: $fileStabilizationDuration,
                    in: 0.5...30.0,
                    step: 0.5
                ) {
                    HStack {
                        Text("Stabilization Duration")
                        Spacer()
                        Text(String(format: "%.1f s", fileStabilizationDuration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Target file stabilization duration")
                .accessibilityValue(String(format: "%.1f seconds", fileStabilizationDuration))
                .accessibilityHint("Adjusts the quiet period required before a target file is considered finished")

                Text("Required quiet period with no file size or timestamp changes before a target file is considered fully written.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Temporary File Extensions Section
            Section("Temporary File Extensions") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Built-in Extensions")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text("crdownload, download, part, tmp, partial, aria2, !ut, utpart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Extensions")
                        .font(.body)

                    TextField("e.g. custompart, tempdownload", text: $customTemporaryExtensions)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Custom temporary file extensions")
                        .accessibilityHint("Comma-separated list of additional extensions to treat as in-progress downloads")
                }

                Text("Comma-separated list of additional file extensions to treat as in-progress downloads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Notifications Section
            Section("Notifications") {
                Toggle("Notify when downloads complete", isOn: $notifyOnDownloadsComplete)
                    .accessibilityLabel("Notify when downloads complete")
                    .accessibilityHint("Send a system notification when all downloads finish")

                Toggle("Notify when target file is ready", isOn: $notifyOnFileDetected)
                    .accessibilityLabel("Notify when target file is ready")
                    .accessibilityHint("Send a system notification when a monitored target file appears and stabilizes")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Actions & Helpers

    private func chooseFolder() {
        let currentURL = URL(fileURLWithPath: watchedDownloadsPath)
        FilePickerHelper.selectFolder(initialURL: currentURL) { selectedURL in
            if let selectedURL {
                watchedDownloadsPath = selectedURL.path(percentEncoded: false)
            }
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
