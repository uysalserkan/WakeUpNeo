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

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "--snapshot"), idx + 1 < args.count {
            let outputDir = args[idx + 1]
            SnapshotRenderer.generateSnapshots(outputDir: outputDir)
            exit(0)
        }
    }

    var body: some Scene {
        // MARK: Menu Bar
        MenuBarExtra {
            MenuBarView()
                .environment(env.sleepManager)
                .environment(env)
        } label: {
            MenuBarIcon(manager: env.sleepManager)
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

// MARK: - Snapshot Renderer (Visual Verification Tooling)

@MainActor
enum SnapshotRenderer {
    static func generateSnapshots(outputDir: String) {
        render(isActive: false, colorScheme: .dark, filename: "menu_inactive.png", outputDir: outputDir)
        render(isActive: true, colorScheme: .dark, filename: "menu_active.png", outputDir: outputDir)
        render(isActive: false, colorScheme: .light, filename: "menu_light.png", outputDir: outputDir)
    }

    private static func render(isActive: Bool, colorScheme: ColorScheme, filename: String, outputDir: String) {
        let env = AppEnvironment()
        if isActive {
            env.sleepManager.start(for: 3600)
        } else {
            env.sleepManager.stop()
        }

        let view = MenuBarView()
            .environment(env.sleepManager)
            .environment(env)
            .environment(\.colorScheme, colorScheme)
            .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))

        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = appearance
        let fittingSize = hostingView.fittingSize
        let width: CGFloat = NativeTheme.popoverWidth
        let height: CGFloat = fittingSize.height > 0 ? fittingSize.height : 376
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
        try? pngData.write(to: url)
        print("Generated snapshot: \(url.path) (size: \(width)x\(height))")
    }
}

