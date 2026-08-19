import SwiftUI
import WakeUpNeoCore

// MARK: - SmartWatchersSectionView

/// Smart Watchers section: "Watch Downloads", "Wait for File…", and "Watch App…".
/// Clean list row appearance with standardized icon alignment and native hover states.
struct SmartWatchersSectionView: View {

    let manager: SleepManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Section Header Label
            Text("SMART WATCHERS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)
                .padding(.bottom, 2)

            // Watcher Rows Stack
            VStack(spacing: NativeTheme.rowSpacing) {
                watchDownloadsRow
                waitForFileRow
                watchAppRow
            }
        }
    }

    // MARK: - 1. Watch Downloads Row

    private var watchDownloadsRow: some View {
        HStack(spacing: 8) {
            MenuRowIcon(
                manager.mode.isWatchingDownloads ? "arrow.down.circle.fill" : "arrow.down.circle",
                color: manager.mode.isWatchingDownloads ? Color.accentColor : Color.secondary
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Watch Downloads")
                    .font(.body)
                    .foregroundStyle(.primary)

                if case .watchingDownloads(let dir, let count) = manager.mode {
                    Text(count > 0 ? "\(count) active (\(dir.lastPathComponent))" : "Watching \(dir.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if manager.mode.isWatchingDownloads {
                Button("Stop") {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Stop watching downloads and sleep after 15 minutes")
                .accessibilityValue("Active")
            } else {
                Button("Start") {
                    let settings = AppSettings.load()
                    manager.startWatchingDownloads(
                        directory: settings.watchedDownloadsURL,
                        customExtensions: settings.parsedCustomExtensions
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Start watching downloads")
                .accessibilityValue("Inactive")
            }
        }
        .padding(.horizontal, NativeTheme.rowHorizontalPadding)
        .padding(.vertical, NativeTheme.rowVerticalPadding)
        .nativeMenuRowHover()
    }

    // MARK: - 2. Wait for File Row

    @ViewBuilder
    private var waitForFileRow: some View {
        if case .waitingForFile(let url) = manager.mode {
            HStack(spacing: 8) {
                MenuRowIcon(
                    manager.isStabilizingFile ? "arrow.triangle.2.circlepath" : "doc.badge.clock.fill",
                    color: Color.accentColor
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(manager.isStabilizingFile ? "Stabilizing File" : "Waiting for File")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Button {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop waiting for file and sleep after 15 minutes")
            }
            .padding(.horizontal, NativeTheme.rowHorizontalPadding)
            .padding(.vertical, NativeTheme.rowVerticalPadding)
            .nativeMenuRowHover()
        } else {
            Button {
                FilePickerHelper.selectTargetFile { selectedURL in
                    guard let selectedURL else { return }
                    let settings = AppSettings.load()
                    manager.startWaitingForFile(
                        at: selectedURL,
                        stabilizationDuration: settings.fileStabilizationDuration
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    MenuRowIcon("doc.badge.clock", color: .secondary)

                    Text("Wait for File…")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, NativeTheme.rowHorizontalPadding)
                .padding(.vertical, NativeTheme.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .accessibilityLabel("Wait for File")
            .accessibilityHint("Select a file to wait for completion before allowing sleep")
        }
    }

    // MARK: - 3. Watch App Row

    @ViewBuilder
    private var watchAppRow: some View {
        if case .watchingProcess(let pid, let name, _) = manager.mode {
            HStack(spacing: 8) {
                MenuRowIcon("app.badge.checkmark.fill", color: Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Watching App")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text("\(name) (PID \(pid))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Button {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop watching app and sleep after 15 minutes")
            }
            .padding(.horizontal, NativeTheme.rowHorizontalPadding)
            .padding(.vertical, NativeTheme.rowVerticalPadding)
            .nativeMenuRowHover()
        } else {
            Button {
                ProcessPickerWindowController.shared.present { target in
                    manager.startWatchingProcess(
                        pid: target.pid,
                        name: target.name,
                        bundleIdentifier: target.bundleIdentifier
                    )
                }
            } label: {
                HStack(spacing: 8) {
                    MenuRowIcon("macwindow.badge.plus", color: .secondary)

                    Text("Watch App…")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, NativeTheme.rowHorizontalPadding)
                .padding(.vertical, NativeTheme.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .accessibilityLabel("Watch Application")
            .accessibilityHint("Select an application or process to keep Mac awake until it terminates")
        }
    }
}
