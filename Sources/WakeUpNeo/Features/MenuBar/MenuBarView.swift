import SwiftUI
import Combine
import WakeUpNeoCore

// MARK: - MenuBarView

/// The native macOS menu bar popover — the primary UI surface in WakeUpNeo.
///
/// Implements a clean, single-surface macOS popover:
/// - One unified popover surface without nested cards or decorative borders.
/// - Native system typography, semantic colors, and subtle system dividers.
/// - Single unified segmented duration control.
/// - Native macOS Toggle switches for power settings.
/// - Precise icon alignment across all rows and sections.
/// - Rock-solid top/leading layout anchoring preventing shift on resize.
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
        VStack(spacing: NativeTheme.cardSpacing) {
            // 1. Primary Controls Card (Header, Duration Pills, Power Options)
            VStack(spacing: 12) {
                MenuBarHeaderView(manager: manager, eyeColor: eyeColor)

                DurationSelectorView(manager: manager, eyeColor: eyeColor)

                PowerOptionsView(
                    keepDisplayAwake: $keepDisplayAwake,
                    preventLidSleep: $preventLidSleep,
                    manager: manager,
                    activeColor: eyeColor
                )
            }
            .liquidGlassCard()

            // 2. Smart Watchers Card
            SmartWatchersSectionView(manager: manager, eyeColor: eyeColor)
                .liquidGlassCard()

            // 3. Optional Update Banner Card
            if let release = env.updateManager.updateAvailable {
                UpdateBannerView(release: release) { targetRelease in
                    env.updateManager.openDownloadLink(for: targetRelease)
                }
                .liquidGlassCard()
            }

            // 4. Footer Actions Card (Settings, Quit)
            MenuBarFooterView(
                onOpenSettings: openSettingsWindow,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .liquidGlassCard()
        }
        .padding(NativeTheme.outerPadding)
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
