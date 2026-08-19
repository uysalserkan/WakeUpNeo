import SwiftUI
import WakeUpNeoCore

// MARK: - MenuBarHeaderView

/// Popover header: Identity (App name + icon), Live Status / Countdown, and Power Action Button.
/// Clean, minimal, native layout with zero enclosing cards and perfectly anchored alignment.
struct MenuBarHeaderView: View {

    let manager: SleepManager
    let eyeColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // App / Status Icon
            Image(systemName: manager.isActive ? "eye.fill" : "eye.slash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(eyeColor)
                .symbolEffect(.bounce, value: manager.isActive)
                .frame(width: 26, height: 26, alignment: .center)
                .accessibilityHidden(true)

            // Title and Subtitle Stack
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 18, alignment: .leading)
            }

            Spacer(minLength: 8)

            // Circular Power Action Button
            Button {
                if manager.isActive {
                    manager.stop()
                } else {
                    let settings = AppSettings.load()
                    manager.start(for: settings.defaultDuration.rawValue)
                }
            } label: {
                Image(systemName: manager.isActive ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(manager.isActive ? eyeColor : Color.secondary.opacity(0.8))
                    .symbolEffect(.bounce, value: manager.isActive)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manager.isActive ? "Stop sleep prevention" : "Start sleep prevention")
            .accessibilityValue(manager.isActive ? "Active" : "Inactive")
            .accessibilityHint("Click to toggle sleep prevention")
        }
    }
}
