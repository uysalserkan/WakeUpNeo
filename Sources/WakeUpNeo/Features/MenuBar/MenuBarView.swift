import SwiftUI
import Combine
import WakeUpNeoCore

// MARK: - MenuBarView

/// The main menu bar popover — the central UI surface in WakeUpNeo.
///
/// Designed to feel like a native macOS Control Center module:
/// - Clean macOS material cards with clear visual hierarchy and balanced spacing.
/// - Native typography, system colors, and standard macOS interaction patterns.
/// - Fully keyboard-navigable and VoiceOver-accessible.
struct MenuBarView: View {

    @Environment(SleepManager.self)   private var manager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings)      private var openSettings
    @Environment(\.colorScheme)       private var colorScheme

    @AppStorage(AppSettingsKeys.keepDisplayAwake) private var keepDisplayAwake = false
    @AppStorage(AppSettingsKeys.preventLidSleep)    private var preventLidSleep    = false
    @AppStorage(AppSettingsKeys.activeIconColor)   private var activeIconColorRaw = "red"

    // Error alert binding
    private var showError: Binding<Bool> {
        Binding(
            get:  { manager.lastError != nil },
            set:  { if !$0 { manager.clearError() } }
        )
    }

    private var eyeColor: Color {
        guard manager.isActive else { return .secondary }
        return (ActiveIconColor(rawValue: activeIconColorRaw) ?? .red).color
    }

    var body: some View {
        VStack(spacing: 8) {
            // 1. Header & Duration Hero Card
            headerCard

            // 2. Smart Watchers Card
            smartWatchersCard

            // 3. Update Banner (when available)
            if env.updateManager.updateAvailable != nil {
                updateBannerCard
            }

            // 4. Footer Actions Card
            footerCard
        }
        .padding(8)
        .frame(width: 272)
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

    // MARK: - 1. Header & Duration Card

    private var headerCard: some View {
        VStack(spacing: 11) {
            // Top Row: App identity, active status, power toggle
            HStack(spacing: 10) {
                Image(systemName: manager.isActive ? "eye.fill" : "eye.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(eyeColor)
                    .liquidGlow(color: eyeColor, radius: 10, isActive: manager.isActive)
                    .symbolEffect(.bounce, value: manager.isActive)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WakeUpNeo")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHeading(.h1)

                    if manager.isActive {
                        CountdownView(manager: manager)
                    } else {
                        Text("Mac can sleep normally")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                // Power Icon Button
                Button {
                    if manager.isActive {
                        manager.stop()
                    } else {
                        let settings = AppSettings.load()
                        manager.start(for: settings.defaultDuration.rawValue)
                    }
                } label: {
                    Image(systemName: manager.isActive ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(eyeColor)
                        .liquidGlow(color: eyeColor, radius: 12, isActive: manager.isActive)
                        .symbolEffect(.bounce, value: manager.isActive)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(manager.isActive ? "Stop sleep prevention" : "Start sleep prevention")
                .accessibilityValue(manager.isActive ? "On" : "Off")
                .accessibilityHint("Click to toggle sleep prevention")
            }

            // Duration & Power Options
            VStack(alignment: .leading, spacing: 9) {
                // Duration Preset Pills Row
                HStack(spacing: 5) {
                    ForEach(DefaultDuration.allCases, id: \.self) { preset in
                        durationPresetButton(preset)
                    }
                    indefinitePresetButton
                }
                .padding(.top, 1)

                // Power Option Pills
                VStack(spacing: 5) {
                    // Keep Display Awake Pill
                    Button {
                        keepDisplayAwake.toggle()
                        manager.keepDisplayAwake = keepDisplayAwake
                    } label: {
                        HStack {
                            Label("Keep Display Awake", systemImage: "sun.max")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(keepDisplayAwake ? "On" : "Off")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 2.5)
                                .background(
                                    ZStack {
                                        if keepDisplayAwake {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [eyeColor.opacity(0.95), eyeColor.opacity(0.75)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        } else {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.08))
                                        }
                                    }
                                )
                                .overlay {
                                    if keepDisplayAwake {
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                                    }
                                }
                                .foregroundStyle(keepDisplayAwake ? Color.white : Color.secondary)
                                .shadow(color: keepDisplayAwake ? eyeColor.opacity(0.3) : .clear, radius: 4, y: 1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .liquidMenuRowHover(cornerRadius: 8)
                    .accessibilityLabel("Keep Display Awake")
                    .accessibilityValue(keepDisplayAwake ? "On" : "Off")

                    // Prevent Lid Sleep Pill
                    Button {
                        preventLidSleep.toggle()
                        manager.preventLidSleep = preventLidSleep
                    } label: {
                        HStack {
                            Label("Prevent Lid Sleep", systemImage: "laptopcomputer")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(preventLidSleep ? "On" : "Off")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 2.5)
                                .background(
                                    ZStack {
                                        if preventLidSleep {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [eyeColor.opacity(0.95), eyeColor.opacity(0.75)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        } else {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.08))
                                        }
                                    }
                                )
                                .overlay {
                                    if preventLidSleep {
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                                    }
                                }
                                .foregroundStyle(preventLidSleep ? Color.white : Color.secondary)
                                .shadow(color: preventLidSleep ? eyeColor.opacity(0.3) : .clear, radius: 4, y: 1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .liquidMenuRowHover(cornerRadius: 8)
                    .accessibilityLabel("Prevent Lid Sleep")
                    .accessibilityValue(preventLidSleep ? "On" : "Off")
                }
                .padding(.top, 1)
            }
        }
        .padding(12)
        .liquidGlassCard(isHighlighted: manager.isActive, glowColor: eyeColor)
    }

    @ViewBuilder
    private func durationPresetButton(_ preset: DefaultDuration) -> some View {
        let isCurrentPreset = manager.mode.isTimed && (manager.sessionDuration == preset.rawValue || abs((manager.mode.endDate?.timeIntervalSinceNow ?? 0) - preset.rawValue) < 2)
        Button {
            manager.start(for: preset.rawValue)
        } label: {
            Text(preset.shortLabel)
        }
        .buttonStyle(LiquidGlassPillButtonStyle(isSelected: isCurrentPreset, tintColor: eyeColor))
        .accessibilityLabel(preset.accessibilityLabel)
    }

    @ViewBuilder
    private var indefinitePresetButton: some View {
        Button {
            manager.startIndefinitely()
        } label: {
            Image(systemName: "infinity")
        }
        .buttonStyle(LiquidGlassPillButtonStyle(isSelected: manager.mode.isIndefinite, tintColor: eyeColor))
        .accessibilityLabel("Start indefinitely — no time limit")
    }

    // MARK: - 2. Smart Watchers Card

    private var smartWatchersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SMART WATCHERS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                watchDownloadsRow
                waitForFileRow
                watchProcessRow
            }
        }
        .padding(11)
        .liquidGlassCard(isHighlighted: manager.mode.isWatchingDownloads || manager.mode.isWaitingForFile || manager.mode.isWatchingProcess)
    }

    private var watchDownloadsRow: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch Downloads")
                        .font(.system(size: 12, weight: .medium))
                    if case .watchingDownloads(let dir, let count) = manager.mode {
                        Text(count > 0 ? "\(count) active (\(dir.lastPathComponent))" : "Watching \(dir.lastPathComponent)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } icon: {
                Image(systemName: manager.mode.isWatchingDownloads ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(manager.mode.isWatchingDownloads ? Color.accentColor : Color.secondary)
                    .liquidGlow(color: .accentColor, radius: 8, isActive: manager.mode.isWatchingDownloads)
            }

            Spacer(minLength: 4)

            if manager.mode.isWatchingDownloads {
                Button {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                } label: {
                    Text("Stop")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clipShape(Capsule())
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
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clipShape(Capsule())
                .accessibilityLabel("Start watching downloads")
                .accessibilityValue("Inactive")
            }
        }
        .liquidMenuRowHover(cornerRadius: 8)
    }

    @ViewBuilder
    private var waitForFileRow: some View {
        if case .waitingForFile(let url) = manager.mode {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(manager.isStabilizingFile ? "Stabilizing File" : "Waiting for File")
                            .font(.system(size: 12, weight: .medium))
                        Text(url.lastPathComponent)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: manager.isStabilizingFile ? "arrow.triangle.2.circlepath" : "doc.badge.clock.fill")
                        .foregroundStyle(Color.accentColor)
                        .liquidGlow(color: .accentColor, radius: 8, isActive: true)
                }

                Spacer(minLength: 4)

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
            .liquidMenuRowHover(cornerRadius: 8)
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidMenuRowHover(cornerRadius: 8)
            .accessibilityLabel("Wait for File")
            .accessibilityHint("Select a file to wait for completion before allowing sleep")
        }
    }

    @ViewBuilder
    private var watchProcessRow: some View {
        if case .watchingProcess(let pid, let name, _) = manager.mode {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Watching App")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(name) (PID \(pid))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: "app.badge.checkmark.fill")
                        .foregroundStyle(Color.accentColor)
                        .liquidGlow(color: .accentColor, radius: 8, isActive: true)
                }

                Spacer(minLength: 4)

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
            .liquidMenuRowHover(cornerRadius: 8)
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
                HStack {
                    Label("Watch App…", systemImage: "macwindow.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidMenuRowHover(cornerRadius: 8)
            .accessibilityLabel("Watch Application")
            .accessibilityHint("Select an application or process to keep Mac awake until it terminates")
        }
    }

    // MARK: - 3. Update Banner Card

    @ViewBuilder
    private var updateBannerCard: some View {
        if let release = env.updateManager.updateAvailable {
            Button {
                env.updateManager.openDownloadLink(for: release)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 16))
                        .liquidGlow(color: .accentColor, radius: 8, isActive: true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update Available")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(release.displayTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text("Update")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                        )
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidGlassCard(cornerRadius: 10, isHighlighted: true, glowColor: .accentColor)
            .accessibilityLabel("Update Available: \(release.displayTitle). Click to update.")
        }
    }

    // MARK: - 4. Footer Actions Card

    private var footerCard: some View {
        VStack(spacing: 2) {
            Button {
                openSettingsWindow()
            } label: {
                HStack {
                    Label("Settings…", systemImage: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("⌘,")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            .liquidMenuRowHover(cornerRadius: 6)
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Label("Quit WakeUpNeo", systemImage: "power")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
            }
            .buttonStyle(.plain)
            .liquidMenuRowHover(cornerRadius: 6)
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit WakeUpNeo")
        }
        .padding(5)
        .liquidGlassCard(cornerRadius: 10)
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey && window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
