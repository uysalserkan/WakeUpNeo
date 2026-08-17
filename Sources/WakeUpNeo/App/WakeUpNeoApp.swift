import SwiftUI
import WakeUpNeoCore

// MARK: - WakeUpNeoApp

/// Application entry point.
///
/// WakeUpNeo runs exclusively as a menu bar utility:
/// - `MenuBarExtra` is the only Scene — there is no main window.
/// - `LSUIElement = YES` in Info.plist suppresses the Dock icon and
///   Cmd+Tab entry at the system level.
/// - The Settings scene provides a native macOS Settings window.
@main
struct WakeUpNeoApp: App {

    @State private var env = AppEnvironment()

    var body: some Scene {
        // MARK: Menu Bar
        MenuBarExtra {
            MenuBarView()
                .environment(env.sleepManager)
                .environment(env)
        } label: {
            MenuBarIcon(isActive: env.sleepManager.isActive)
        }
        .menuBarExtraStyle(.window)

        // MARK: Settings (⌘,)
        Settings {
            SettingsView()
                .environment(env.sleepManager)
                .environment(env)
        }
    }
}
