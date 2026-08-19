import SwiftUI
import WakeUpNeoCore

// MARK: - SmartWatchersSectionView

/// Smart Watchers section: "Watch Downloads", "Wait for File…", and "Watch App…".
/// Clean list row appearance with standardized icon alignment and native hover states.
struct SmartWatchersSectionView: View {

    let manager: SleepManager
    var eyeColor: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header Label
            Text("SMART WATCHERS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
                .tracking(0.6)
                .padding(.leading, 2)

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
                color: manager.mode.isWatchingDownloads ? eyeColor : Color.secondary
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Watch Downloads")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                if case .watchingDownloads(let dir, let count) = manager.mode {
                    Text(count > 0 ? "\(count) active (\(dir.lastPathComponent))" : "Watching Downloads")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if manager.mode.isWatchingDownloads {
                Button {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                } label: {
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .liquidGlassPill(isSelected: true, activeColor: eyeColor)
                .accessibilityLabel("Stop watching downloads and sleep after 15 minutes")
                .accessibilityValue("Active")
            } else {
                Button {
                    let settings = AppSettings.load()
                    manager.startWatchingDownloads(
                        directory: settings.watchedDownloadsURL,
                        customExtensions: settings.parsedCustomExtensions
                    )
                } label: {
                    Text("Start")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 58, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .liquidGlassPill(isSelected: false)
                .accessibilityLabel("Start watching downloads")
                .accessibilityValue("Inactive")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    // MARK: - 2. Wait for File Row

    @ViewBuilder
    private var waitForFileRow: some View {
        if case .waitingForFile(let url) = manager.mode {
            HStack(spacing: 8) {
                MenuRowIcon(
                    manager.isStabilizingFile ? "arrow.triangle.2.circlepath" : "doc.badge.clock.fill",
                    color: eyeColor
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(manager.isStabilizingFile ? "Stabilizing File" : "Waiting for File")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(url.lastPathComponent)
                        .font(.system(size: 11))
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
                        .foregroundStyle(.secondary.opacity(0.8))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop waiting for file and sleep after 15 minutes")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
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

                    Text("Wait for File...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
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
                MenuRowIcon("app.badge.checkmark.fill", color: eyeColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Watching App")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Text("\(name) (PID \(pid))")
                        .font(.system(size: 11))
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
                        .foregroundStyle(.secondary.opacity(0.8))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop watching app and sleep after 15 minutes")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
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

                    Text("Watch App...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .accessibilityLabel("Watch Application")
            .accessibilityHint("Select an application or process to keep Mac awake until it terminates")
        }
    }
}
