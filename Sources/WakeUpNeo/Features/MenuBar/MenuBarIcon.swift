import SwiftUI
import WakeUpNeoCore

// MARK: - MenuBarIcon

/// The image and optional countdown shown in the system menu bar for WakeUpNeo.
///
/// - Inactive: `eye.slash` — subtle monochrome.
/// - Active: `eye.fill` — rendered in the user-customizable color from Settings.
/// - When `showCountdownInMenuBar` is enabled in Settings and a timed session is active,
///   displays the remaining countdown time next to the icon.
struct MenuBarIcon: View {

    private let manager: SleepManager?
    private let fallbackMode: SleepMode

    @AppStorage(AppSettingsKeys.showCountdownInMenuBar) private var showCountdownInMenuBar = true
    @AppStorage(AppSettingsKeys.activeIconColor) private var activeIconColorRaw = "red"

    init(manager: SleepManager) {
        self.manager = manager
        self.fallbackMode = .off
    }

    init(mode: SleepMode) {
        self.manager = nil
        self.fallbackMode = mode
    }

    init(isActive: Bool) {
        self.manager = nil
        self.fallbackMode = isActive ? .indefinite : .off
    }

    private var currentMode: SleepMode {
        manager?.mode ?? fallbackMode
    }

    private var remainingTime: TimeInterval {
        manager?.remainingTime ?? 0
    }

    var activeColor: Color {
        (ActiveIconColor(rawValue: activeIconColorRaw) ?? .red).color
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: currentMode.isActive ? "eye.fill" : "eye.slash")
                .symbolEffect(.bounce, value: currentMode)
                .foregroundStyle(currentMode.isActive ? activeColor : .primary)

            if showCountdownInMenuBar && currentMode.isActive {
                if case .timed = currentMode, remainingTime > 0 {
                    Text(formattedCountdown)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                } else if case .watchingDownloads(_, let count) = currentMode, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityLabel(accessibilityLabelText)
    }

    private var formattedCountdown: String {
        let total = max(0, Int(remainingTime))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private var accessibilityLabelText: String {
        if currentMode.isActive {
            if showCountdownInMenuBar && currentMode.isTimed {
                return "WakeUpNeo is active, \(formattedCountdown) remaining"
            }
            return "WakeUpNeo is active (\(currentMode.statusTitle))"
        }
        return "WakeUpNeo is inactive"
    }
}
