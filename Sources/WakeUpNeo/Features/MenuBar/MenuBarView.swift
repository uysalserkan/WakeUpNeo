import SwiftUI
import Combine
import WakeUpNeoCore

// MARK: - MenuBarView

/// The native macOS menu bar popover — the primary UI surface in WakeUpNeo.
///
/// Implements a clean, single-surface macOS popover:
/// - One unified popover surface without nested cards or excessive outlines.
/// - Native system typography, semantic colors, and subtle dividers.
/// - Unified segmented duration selector.
/// - Native macOS Toggle switches for power settings.
/// - Clear, calm visual hierarchy with stable top/leading layout anchoring.
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
        VStack(alignment: .leading, spacing: 0) {
            // 1. Header (Identity, Live Countdown / Status, Power Toggle)
            headerSection
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            // 2. Duration Selector (Single Unified Segmented Control)
            durationSection
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // 3. Sleep & Display Options (Native macOS Toggles)
            optionsSection
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Divider
            Divider()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // 4. Smart Watchers Section
            smartWatchersSection
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // 5. Optional Update Banner
            if env.updateManager.updateAvailable != nil {
                updateBannerSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            // Divider
            Divider()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // 6. Footer Actions (Settings, Quit)
            footerSection
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: NativeTheme.popoverWidth)
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

    // MARK: - 1. Header Section

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: manager.isActive ? "eye.fill" : "eye.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(eyeColor)
                .symbolEffect(.bounce, value: manager.isActive)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("WakeUpNeo")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityHeading(.h1)

                Group {
                    if manager.isActive {
                        CountdownView(manager: manager)
                    } else {
                        Text("Mac can sleep normally")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(height: 16, alignment: .leading)
            }

            Spacer(minLength: 8)

            Button {
                if manager.isActive {
                    manager.stop()
                } else {
                    let settings = AppSettings.load()
                    manager.start(for: settings.defaultDuration.rawValue)
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
    }

    // MARK: - 2. Duration Selector (Single Segmented Control)

    private var durationSection: some View {
        HStack(spacing: 2) {
            ForEach(DefaultDuration.allCases, id: \.self) { preset in
                durationSegmentButton(preset)
            }
            indefiniteSegmentButton
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: NativeTheme.segmentedCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.6 : 0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: NativeTheme.segmentedCornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.3 : 0.15), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func durationSegmentButton(_ preset: DefaultDuration) -> some View {
        let isSelected = manager.mode.isTimed && (manager.sessionDuration == preset.rawValue || abs((manager.mode.endDate?.timeIntervalSinceNow ?? 0) - preset.rawValue) < 2)
        Button {
            manager.start(for: preset.rawValue)
        } label: {
            Text(preset.shortLabel)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: NativeTheme.innerSegmentCornerRadius, style: .continuous)
                            .fill(manager.isActive ? eyeColor : Color.accentColor)
                            .shadow(color: Color.black.opacity(0.15), radius: 1, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.accessibilityLabel)
    }

    @ViewBuilder
    private var indefiniteSegmentButton: some View {
        let isSelected = manager.mode.isIndefinite
        Button {
            manager.startIndefinitely()
        } label: {
            Image(systemName: "infinity")
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: NativeTheme.innerSegmentCornerRadius, style: .continuous)
                            .fill(manager.isActive ? eyeColor : Color.accentColor)
                            .shadow(color: Color.black.opacity(0.15), radius: 1, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start indefinitely — no time limit")
    }

    // MARK: - 3. Sleep & Power Options (Native Toggles)

    private var optionsSection: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $keepDisplayAwake) {
                Label("Keep Display Awake", systemImage: "sun.max")
                    .font(.body)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: keepDisplayAwake) { _, newValue in
                manager.keepDisplayAwake = newValue
            }
            .accessibilityLabel("Keep Display Awake")

            Toggle(isOn: $preventLidSleep) {
                Label("Prevent Lid Sleep", systemImage: "laptopcomputer")
                    .font(.body)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: preventLidSleep) { _, newValue in
                manager.preventLidSleep = newValue
            }
            .accessibilityLabel("Prevent Lid Sleep")
        }
    }

    // MARK: - 4. Smart Watchers Section

    private var smartWatchersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SMART WATCHERS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 4)
                .padding(.bottom, 2)

            VStack(spacing: 2) {
                watchDownloadsRow
                waitForFileRow
                watchProcessRow
            }
        }
    }

    private var watchDownloadsRow: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch Downloads")
                        .font(.body)
                    if case .watchingDownloads(let dir, let count) = manager.mode {
                        Text(count > 0 ? "\(count) active (\(dir.lastPathComponent))" : "Watching \(dir.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } icon: {
                Image(systemName: manager.mode.isWatchingDownloads ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(manager.mode.isWatchingDownloads ? Color.accentColor : Color.secondary)
                    .font(.system(size: 15))
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
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .nativeMenuRowHover()
    }

    @ViewBuilder
    private var waitForFileRow: some View {
        if case .waitingForFile(let url) = manager.mode {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(manager.isStabilizingFile ? "Stabilizing File" : "Waiting for File")
                            .font(.body)
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: manager.isStabilizingFile ? "arrow.triangle.2.circlepath" : "doc.badge.clock.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 15))
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
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
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
                HStack {
                    Label("Wait for File…", systemImage: "doc.badge.clock")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
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
                            .font(.body)
                        Text("\(name) (PID \(pid))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: "app.badge.checkmark.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 15))
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
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
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
                HStack {
                    Label("Watch App…", systemImage: "macwindow.badge.plus")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .accessibilityLabel("Watch Application")
            .accessibilityHint("Select an application or process to keep Mac awake until it terminates")
        }
    }

    // MARK: - 5. Update Banner Section

    @ViewBuilder
    private var updateBannerSection: some View {
        if let release = env.updateManager.updateAvailable {
            Button {
                env.updateManager.openDownloadLink(for: release)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 15))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update Available")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(release.displayTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("Update")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Update Available: \(release.displayTitle). Click to update.")
        }
    }

    // MARK: - 6. Footer Section

    private var footerSection: some View {
        VStack(spacing: 2) {
            Button {
                openSettingsWindow()
            } label: {
                HStack {
                    Label("Settings…", systemImage: "gearshape")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("⌘,")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
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
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .nativeMenuRowHover()
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit WakeUpNeo")
        }
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
