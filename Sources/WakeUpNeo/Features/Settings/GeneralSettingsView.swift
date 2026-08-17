import SwiftUI
import WakeUpNeoCore

// MARK: - GeneralSettingsView

/// The General tab in Settings: startup, countdown, notifications,
/// and default duration.
struct GeneralSettingsView: View {

    @AppStorage(AppSettingsKeys.launchAtLogin)          private var launchAtLogin          = true
    @AppStorage(AppSettingsKeys.showCountdownInMenuBar) private var showCountdownInMenuBar = true
    @AppStorage(AppSettingsKeys.notifyOnSessionEnd)     private var notifyOnSessionEnd      = true
    @AppStorage(AppSettingsKeys.notifyOnSessionExpiring) private var notifyOnSessionExpiring = false
    @AppStorage(AppSettingsKeys.defaultDuration)        private var defaultDurationRaw: Double = DefaultDuration.oneHour.rawValue

    @State private var launchLoginError: Error?

    private let loginService = LaunchAtLoginService()

    // Bidirectional binding between Double storage and the typed enum
    private var defaultDuration: Binding<DefaultDuration> {
        Binding(
            get: { DefaultDuration(rawValue: defaultDurationRaw) ?? .oneHour },
            set: { defaultDurationRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .accessibilityLabel("Launch WakeUpNeo automatically at login")
                if let error = launchLoginError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Menu Bar") {
                Toggle("Show Countdown in Menu Bar", isOn: $showCountdownInMenuBar)
                    .accessibilityLabel("Show the remaining session time in the menu bar label")
            }

            Section("Notifications") {
                Toggle("Notify When Session Ends", isOn: $notifyOnSessionEnd)
                    .accessibilityLabel("Send a notification when the WakeUpNeo session finishes")

                Toggle("Notify 5 Minutes Before End", isOn: $notifyOnSessionExpiring)
                    .accessibilityLabel("Send a notification 5 minutes before the session ends")
            }

            Section("Default Duration") {
                Picker("Duration", selection: defaultDuration) {
                    ForEach(DefaultDuration.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Default session duration when starting without specifying a time")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - LaunchAtLogin Binding

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                launchAtLogin = newValue
                launchLoginError = nil
                do {
                    if newValue {
                        try loginService.enable()
                    } else {
                        try loginService.disable()
                    }
                } catch {
                    // Revert the storage value on failure
                    launchAtLogin    = !newValue
                    launchLoginError = error
                }
            }
        )
    }
}
