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
                ZStack {
                    Circle()
                        .fill(
                            manager.isActive
                                ? eyeColor
                                : Color.white.opacity(0.08)
                        )
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    manager.isActive
                                        ? Color.white.opacity(0.20)
                                        : Color.white.opacity(0.12),
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(
                            color: manager.isActive ? eyeColor.opacity(0.40) : Color.clear,
                            radius: 5,
                            y: 2
                        )

                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(manager.isActive ? Color.white : Color.primary.opacity(0.85))
                        .symbolEffect(.bounce, value: manager.isActive)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(manager.isActive ? "Stop sleep prevention" : "Start sleep prevention")
            .accessibilityValue(manager.isActive ? "Active" : "Inactive")
            .accessibilityHint("Click to toggle sleep prevention")
        }
    }
}
