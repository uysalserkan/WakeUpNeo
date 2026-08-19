import SwiftUI
import WakeUpNeoCore

// MARK: - PowerOptionsView

/// Power options section: "Keep Display Awake" and "Prevent Lid Sleep".
/// Uses native macOS switch toggles with standardized icon alignment.
struct PowerOptionsView: View {

    @Binding var keepDisplayAwake: Bool
    @Binding var preventLidSleep: Bool
    let manager: SleepManager
    var activeColor: Color = .accentColor

    var body: some View {
        VStack(spacing: 8) {
            // Keep Display Awake Row
            HStack(spacing: 8) {
                MenuRowIcon("sun.max", color: keepDisplayAwake ? .primary : .secondary)

                Text("Keep Display Awake")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        keepDisplayAwake.toggle()
                        manager.keepDisplayAwake = keepDisplayAwake
                    }
                } label: {
                    Text(keepDisplayAwake ? "On" : "Off")
                        .font(.system(size: 12, weight: keepDisplayAwake ? .semibold : .medium))
                        .foregroundStyle(keepDisplayAwake ? Color.white : Color.secondary)
                        .frame(width: 44, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .liquidGlassPill(isSelected: keepDisplayAwake, activeColor: activeColor)
                .accessibilityLabel("Keep Display Awake")
                .accessibilityValue(keepDisplayAwake ? "On" : "Off")
            }

            // Prevent Lid Sleep Row
            HStack(spacing: 8) {
                MenuRowIcon("laptopcomputer", color: preventLidSleep ? .primary : .secondary)

                Text("Prevent Lid Sleep")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        preventLidSleep.toggle()
                        manager.preventLidSleep = preventLidSleep
                    }
                } label: {
                    Text(preventLidSleep ? "On" : "Off")
                        .font(.system(size: 12, weight: preventLidSleep ? .semibold : .medium))
                        .foregroundStyle(preventLidSleep ? Color.white : Color.secondary)
                        .frame(width: 44, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .liquidGlassPill(isSelected: preventLidSleep, activeColor: activeColor)
                .accessibilityLabel("Prevent Lid Sleep")
                .accessibilityValue(preventLidSleep ? "On" : "Off")
            }
        }
    }
}
