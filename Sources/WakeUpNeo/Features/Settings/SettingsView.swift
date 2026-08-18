import SwiftUI
import WakeUpNeoCore

// MARK: - SettingsTab

/// Available tabs in the WakeUpNeo Settings window.
public enum SettingsTab: Int, Hashable, CaseIterable, Identifiable {
    case general
    case monitoring
    case power
    case about

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .general:    return "General"
        case .monitoring: return "Monitoring"
        case .power:      return "Power"
        case .about:      return "About"
        }
    }

    public var iconName: String {
        switch self {
        case .general:    return "gearshape"
        case .monitoring: return "arrow.down.circle"
        case .power:      return "bolt"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - SettingsView

/// Native macOS Settings window (⌘,) with tabbed navigation.
///
/// Uses `TabView` — the standard macOS settings pattern — with
/// labeled tabs matching System Settings conventions.
struct SettingsView: View {

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label(SettingsTab.general.title, systemImage: SettingsTab.general.iconName)
                }
                .tag(SettingsTab.general)

            MonitoringSettingsView()
                .tabItem {
                    Label(SettingsTab.monitoring.title, systemImage: SettingsTab.monitoring.iconName)
                }
                .tag(SettingsTab.monitoring)

            PowerSettingsView()
                .tabItem {
                    Label(SettingsTab.power.title, systemImage: SettingsTab.power.iconName)
                }
                .tag(SettingsTab.power)

            AboutView()
                .tabItem {
                    Label(SettingsTab.about.title, systemImage: SettingsTab.about.iconName)
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 480, height: 440)
    }
}
