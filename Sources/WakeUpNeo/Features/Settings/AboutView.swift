import SwiftUI
import WakeUpNeoCore

// MARK: - AboutView

/// About screen: app icon, name, version, Matrix tagline, and update status.
/// Matches standard macOS About panel styling.
struct AboutView: View {

    @Environment(AppEnvironment.self) private var env

    private var updateManager: UpdateManager {
        env.updateManager
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.16"
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            appIconView
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("WakeUpNeo")
                    .font(.title2.weight(.bold))

                Text(versionString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                Text("Wake up, Neo.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Text("Stay awake. Stay out of the way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)

            Divider()
                .padding(.horizontal, 32)

            // MARK: - Update Status Section
            updateSection

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var appIconView: some View {
        if let icon = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "eye.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        if updateManager.isChecking {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if let release = updateManager.updateAvailable {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Update Available: \(release.displayTitle)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 8) {
                    Button("Update Now") {
                        updateManager.openDownloadLink(for: release)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Release Notes") {
                        updateManager.openReleasePage(for: release)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
        } else {
            VStack(spacing: 8) {
                if updateManager.isUpToDate {
                    Text("WakeUpNeo is up to date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = updateManager.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if let lastChecked = updateManager.lastCheckedDate {
                    Text("Last checked: \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button("Check for Updates") {
                    Task {
                        await updateManager.checkForUpdates(manual: true)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Check for software updates")
            }
        }
    }
}
