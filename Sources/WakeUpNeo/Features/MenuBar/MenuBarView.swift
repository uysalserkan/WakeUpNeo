import SwiftUI
import Combine
import WakeUpNeoCore

// MARK: - Popover Window Sizing

/// Reports the popover content's natural height so the panel window can be forced to match it.
///
/// MenuBarExtra `.window` panels do not reliably shrink (or restore) their window to fit the
/// content, leaving the popover stuck at a stale, taller height with the content floating in an
/// empty space. Measuring the content height and applying it to the window keeps the panel
/// perfectly sized in both the collapsed and expanded states.
private struct PopoverContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Bridges the popover's `NSWindow` into SwiftUI so its size can be corrected.
private struct PopoverWindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

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

    @State private var isTimeSectionExpanded = false

    @State private var popoverWindow: NSWindow?
    @State private var contentHeight: CGFloat = 0

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

    private var shouldShowDurationSection: Bool {
        isTimeSectionExpanded || manager.isActive
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
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: PopoverContentHeightKey.self, value: proxy.size.height)
            }
        )
        .frame(width: 272)
        .fixedSize(horizontal: false, vertical: true)
        .background(PopoverWindowAccessor { popoverWindow = $0 })
        .onPreferenceChange(PopoverContentHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
            applyPopoverContentHeight()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === popoverWindow else { return }
            applyPopoverContentHeight()
        }
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

    /// Forces the popover panel window to exactly match the content's natural size.
    ///
    /// MenuBarExtra `.window` panels do not reliably shrink to fit their content (or restore a
    /// stale larger frame), so we correct the window height explicitly whenever the content height
    /// changes or the panel becomes key again.
    private func applyPopoverContentHeight() {
        let window = popoverWindow
        let height = contentHeight
        DispatchQueue.main.async {
            guard let window, window.isVisible, height > 0 else { return }
            let target = NSSize(width: 272, height: height)
            guard abs(window.frame.size.height - target.height) > 1 else { return }
            var newFrame = window.frame
            newFrame.size = target
            window.setFrame(newFrame, display: true, animate: false)
        }
    }

    // MARK: - 1. Header & Duration Card

    private var headerCard: some View {
        VStack(spacing: 10) {
            // Top Row: App identity, active status, power toggle
            HStack(spacing: 10) {
                Image(systemName: manager.isActive ? "eye.fill" : "eye.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(eyeColor)
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
                        isTimeSectionExpanded = false
                    } else {
                        let settings = AppSettings.load()
                        manager.start(for: settings.defaultDuration.rawValue)
                        isTimeSectionExpanded = true
                    }
                } label: {
                    Image(systemName: manager.isActive ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(eyeColor)
                        .symbolEffect(.bounce, value: manager.isActive)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(manager.isActive ? "Stop sleep prevention" : "Start sleep prevention")
                .accessibilityValue(manager.isActive ? "On" : "Off")
                .accessibilityHint("Click to toggle sleep prevention")
            }

            // Expandable Duration & Power Options
            if shouldShowDurationSection {
                VStack(alignment: .leading, spacing: 8) {
                    // Duration Preset Pills Row
                    HStack(spacing: 5) {
                        ForEach(DefaultDuration.allCases, id: \.self) { preset in
                            durationPresetButton(preset)
                        }
                        indefinitePresetButton
                    }
                    .padding(.top, 2)

                    // Power Option Pills
                    VStack(spacing: 5) {
                        // Keep Display Awake Pill
                        Button {
                            keepDisplayAwake.toggle()
                            manager.keepDisplayAwake = keepDisplayAwake
                        } label: {
                            HStack {
                                Label("Keep Display Awake", systemImage: "sun.max")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(keepDisplayAwake ? "On" : "Off")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(keepDisplayAwake ? eyeColor : Color.primary.opacity(0.08))
                                    .foregroundStyle(keepDisplayAwake ? Color.white : Color.secondary)
                                    .clipShape(Capsule())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Keep Display Awake")
                        .accessibilityValue(keepDisplayAwake ? "On" : "Off")

                        // Prevent Lid Sleep Pill
                        Button {
                            preventLidSleep.toggle()
                            manager.preventLidSleep = preventLidSleep
                        } label: {
                            HStack {
                                Label("Prevent Lid Sleep", systemImage: "laptopcomputer")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(preventLidSleep ? "On" : "Off")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(preventLidSleep ? eyeColor : Color.primary.opacity(0.08))
                                    .foregroundStyle(preventLidSleep ? Color.white : Color.secondary)
                                    .clipShape(Capsule())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Prevent Lid Sleep")
                        .accessibilityValue(preventLidSleep ? "On" : "Off")
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(11)
        .nativeMacOSCard(isHighlighted: false)
    }

    @ViewBuilder
    private func durationPresetButton(_ preset: DefaultDuration) -> some View {
        let isCurrentPreset = manager.mode.isTimed && abs((manager.mode.endDate?.timeIntervalSinceNow ?? 0) - preset.rawValue) < 2
        if isCurrentPreset {
            Button {
                manager.start(for: preset.rawValue)
            } label: {
                Text(preset.shortLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(eyeColor)
            .controlSize(.small)
            .clipShape(Capsule())
            .accessibilityLabel(preset.accessibilityLabel)
        } else {
            Button {
                manager.start(for: preset.rawValue)
            } label: {
                Text(preset.shortLabel)
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .clipShape(Capsule())
            .accessibilityLabel(preset.accessibilityLabel)
        }
    }

    @ViewBuilder
    private var indefinitePresetButton: some View {
        if manager.mode.isIndefinite {
            Button {
                manager.startIndefinitely()
            } label: {
                Image(systemName: "infinity")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(eyeColor)
            .controlSize(.small)
            .clipShape(Capsule())
            .accessibilityLabel("Start indefinitely — no time limit")
        } else {
            Button {
                manager.startIndefinitely()
            } label: {
                Image(systemName: "infinity")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .clipShape(Capsule())
            .accessibilityLabel("Start indefinitely — no time limit")
        }
    }

    // MARK: - 2. Smart Watchers Card

    private var smartWatchersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SMART WATCHERS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)

            VStack(spacing: 8) {
                watchDownloadsRow
                waitForFileRow
                watchProcessRow
            }
        }
        .padding(11)
        .nativeMacOSCard(isHighlighted: false)
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
            }

            Spacer(minLength: 4)

            if manager.mode.isWatchingDownloads {
                Button {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                    isTimeSectionExpanded = true
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
                }

                Spacer(minLength: 4)

                Button {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                    isTimeSectionExpanded = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop waiting for file and sleep after 15 minutes")
            }
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
                }

                Spacer(minLength: 4)

                Button {
                    UserDefaults.standard.set(DefaultDuration.fifteenMinutes.rawValue, forKey: AppSettingsKeys.defaultDuration)
                    manager.start(for: DefaultDuration.fifteenMinutes.rawValue)
                    isTimeSectionExpanded = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop watching app and sleep after 15 minutes")
            }
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.16))
                        .clipShape(Capsule())
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                        .font(.system(size: 12))
                    Spacer()
                    Text("⌘,")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Label("Quit WakeUpNeo", systemImage: "power")
                        .font(.system(size: 12))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit WakeUpNeo")
        }
        .padding(4)
        .nativeMacOSCard(cornerRadius: 10)
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
