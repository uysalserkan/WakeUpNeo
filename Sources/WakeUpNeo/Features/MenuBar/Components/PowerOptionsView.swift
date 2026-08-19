import SwiftUI
import WakeUpNeoCore

// MARK: - PowerOptionsView

/// Power options section: "Keep Display Awake" and "Prevent Lid Sleep".
/// Uses native macOS switch toggles with standardized icon alignment.
struct PowerOptionsView: View {

    @Binding var keepDisplayAwake: Bool
    @Binding var preventLidSleep: Bool
    let manager: SleepManager

    var body: some View {
        VStack(spacing: 8) {
            // Keep Display Awake Toggle
            Toggle(isOn: $keepDisplayAwake) {
                HStack(spacing: 8) {
                    MenuRowIcon("sun.max", color: keepDisplayAwake ? .primary : .secondary)
                    Text("Keep Display Awake")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: keepDisplayAwake) { _, newValue in
                manager.keepDisplayAwake = newValue
            }
            .accessibilityLabel("Keep Display Awake")

            // Prevent Lid Sleep Toggle
            Toggle(isOn: $preventLidSleep) {
                HStack(spacing: 8) {
                    MenuRowIcon("laptopcomputer", color: preventLidSleep ? .primary : .secondary)
                    Text("Prevent Lid Sleep")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: preventLidSleep) { _, newValue in
                manager.preventLidSleep = newValue
            }
            .accessibilityLabel("Prevent Lid Sleep")
        }
    }
}
