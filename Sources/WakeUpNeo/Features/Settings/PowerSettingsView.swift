import SwiftUI
import WakeUpNeoCore

// MARK: - PowerSettingsView

/// The Power tab in Settings: independent system-sleep and display-sleep
/// toggles, with a contextual explanation.
///
/// System sleep and display sleep are intentionally separate — the default
/// is to prevent system sleep while allowing the display to sleep.
struct PowerSettingsView: View {

    @Environment(SleepManager.self) private var manager

    @AppStorage(AppSettingsKeys.preventSystemSleep) private var preventSystemSleep = true
    @AppStorage(AppSettingsKeys.keepDisplayAwake)   private var keepDisplayAwake   = false
    @AppStorage(AppSettingsKeys.preventLidSleep)    private var preventLidSleep    = false

    var body: some View {
        Form {
            Section("Sleep Prevention") {
                Toggle("Prevent System Sleep", isOn: $preventSystemSleep)
                    .accessibilityLabel("Prevent the system from sleeping due to user inactivity")
                    .onChange(of: preventSystemSleep) { _, newValue in
                        manager.preventSystemSleep = newValue
                    }

                Toggle("Keep Display Awake", isOn: $keepDisplayAwake)
                    .accessibilityLabel("Also prevent the display from sleeping")
                    .onChange(of: keepDisplayAwake) { _, newValue in
                        manager.keepDisplayAwake = newValue
                    }

                Toggle("Prevent Sleep on Lid Close", isOn: $preventLidSleep)
                    .accessibilityLabel("Keep the Mac awake even when the laptop lid is closed")
                    .onChange(of: preventLidSleep) { _, newValue in
                        manager.preventLidSleep = newValue
                    }
            }

            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Independent power controls")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text("WakeUpNeo cooperates with macOS power management. You can allow the display to sleep while the system stays awake — useful for background downloads.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Lid-close prevention keeps the Mac awake when the laptop lid is shut (closed-display mode). Ensure proper airflow and ventilation if keeping the Mac in a bag or closed sleeve.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
