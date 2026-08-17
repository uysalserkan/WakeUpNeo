import SwiftUI
import WakeUpNeoCore

// MARK: - MenuBarView

/// The main menu bar popover — the central UI surface in WakeUpNeo.
///
/// Design goals:
/// - The user understands the current state within one second of opening.
/// - Controls are immediately reachable with a single click.
/// - No dashboard aesthetic; no unnecessary visual noise.
/// - Fully keyboard-navigable and VoiceOver-accessible.
struct MenuBarView: View {

    @Environment(SleepManager.self)   private var manager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings)      private var openSettings

    @AppStorage(AppSettingsKeys.keepDisplayAwake) private var keepDisplayAwake = false
    @AppStorage(AppSettingsKeys.preventLidSleep)    private var preventLidSleep    = false

    // Error alert binding
    private var showError: Binding<Bool> {
        Binding(
            get:  { manager.lastError != nil },
            set:  { if !$0 { manager.clearError() } }
        )
    }

    // Prevent Sleep toggle binding
    private var sleepPreventionOn: Binding<Bool> {
        Binding(
            get: { manager.isActive },
            set: { on in
                if on { manager.startIndefinitely() } else { manager.stop() }
            }
        )
    }

    // Watch Downloads toggle binding
    private var watchDownloadsBinding: Binding<Bool> {
        Binding(
            get: { manager.mode.isWatchingDownloads },
            set: { on in
                if on {
                    let settings = AppSettings.load()
                    manager.startWatchingDownloads(
                        directory: settings.watchedDownloadsURL,
                        customExtensions: settings.parsedCustomExtensions
                    )
                } else {
                    manager.stop()
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            controlsSection
            Divider()
            durationSection
            Divider()
            smartWatchersSection
            Divider()
            footerSection
        }
        .frame(width: 280)
        .alert("Unable to Prevent Sleep", isPresented: showError) {
            Button("Try Again") {
                manager.clearError()
                manager.startIndefinitely()
            }
            Button("Cancel", role: .cancel) {
                manager.clearError()
            }
        } message: {
            if let error = manager.lastError {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: manager.isActive ? "eye.fill" : "eye.slash")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(manager.isActive ? Color.accentColor : Color.secondary)
                .symbolEffect(.bounce, value: manager.isActive)
                .padding(.top, 18)
                .accessibilityHidden(true)

            Text("WakeUpNeo")
                .font(.headline)
                .accessibilityHeading(.h1)

            if manager.isActive {
                CountdownView(manager: manager)
            } else {
                Text("Your Mac can sleep normally")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Main Toggle

    private var controlsSection: some View {
        Toggle(isOn: sleepPreventionOn) {
            Label("Prevent Sleep", systemImage: "powersleep")
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityLabel("Prevent Sleep")
        .accessibilityValue(manager.isActive ? "On" : "Off")
        .accessibilityHint("Toggle to start or stop sleep prevention")
    }

    // MARK: - Duration Picker

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Duration")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            HStack(spacing: 6) {
                ForEach(DefaultDuration.allCases) { preset in
                    durationButton(preset)
                }
                indefiniteButton
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 12)

            Toggle(isOn: $keepDisplayAwake) {
                Label("Keep Display Awake", systemImage: "sun.max")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .onChange(of: keepDisplayAwake) { _, newValue in
                manager.keepDisplayAwake = newValue
            }
            .accessibilityLabel("Keep Display Awake")
            .accessibilityHint("Also prevent the display from sleeping")

            Toggle(isOn: $preventLidSleep) {
                Label("Prevent Lid Sleep", systemImage: "laptopcomputer")
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .onChange(of: preventLidSleep) { _, newValue in
                manager.preventLidSleep = newValue
            }
            .accessibilityLabel("Prevent Lid Sleep")
            .accessibilityHint("Prevent the Mac from sleeping when the lid is closed")
        }
    }

    private func durationButton(_ preset: DefaultDuration) -> some View {
        Button {
            manager.start(for: preset.rawValue)
        } label: {
            Text(preset.shortLabel)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(preset.accessibilityLabel)
    }

    private var indefiniteButton: some View {
        Button {
            manager.startIndefinitely()
        } label: {
            Image(systemName: "infinity")
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Start indefinitely — no time limit")
    }

    // MARK: - Smart Watchers

    private var smartWatchersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Smart Watchers")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            watchDownloadsRow

            Divider()
                .padding(.horizontal, 12)

            waitForFileRow
        }
        .padding(.bottom, 10)
    }

    private var watchDownloadsRow: some View {
        Toggle(isOn: watchDownloadsBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Watch Downloads", systemImage: manager.mode.isWatchingDownloads ? "arrow.down.circle.fill" : "arrow.down.circle")
                if case .watchingDownloads(let dir, let count) = manager.mode {
                    Text(count > 0 ? "\(count) active (\(dir.lastPathComponent))" : "Watching \(dir.lastPathComponent)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .accessibilityLabel("Watch Downloads")
        .accessibilityValue(manager.mode.isWatchingDownloads ? "On" : "Off")
        .accessibilityHint("Keep Mac awake while files are downloading in the watched directory")
    }

    @ViewBuilder
    private var waitForFileRow: some View {
        if case .waitingForFile(let url) = manager.mode {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(manager.isStabilizingFile ? "Stabilizing File" : "Waiting for File")
                            .font(.body)
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: manager.isStabilizingFile ? "arrow.triangle.2.circlepath" : "doc.badge.clock.fill")
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Button {
                    manager.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop waiting for file")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
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
                HStack {
                    Label("Wait for File…", systemImage: "doc.badge.clock")
                        .font(.body)
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .accessibilityLabel("Wait for File")
            .accessibilityHint("Select a file to wait for completion before allowing sleep")
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Button {
                // Opens the Settings window (works with the Settings scene)
                openSettings()
                // Dismiss the popover
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                footerRow(title: "Settings", trailing: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                })
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                footerRow(title: "Quit WakeUpNeo", trailing: {
                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                })
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit WakeUpNeo")
        }
    }

    @ViewBuilder
    private func footerRow<Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title)
                .font(.body)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
