import SwiftUI

// MARK: - AboutView

/// About screen: app icon, name, version, and Matrix tagline.
/// Feels like a built-in macOS utility's About panel.
struct AboutView: View {

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
        let build   = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)

                Image(systemName: "eye.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("WakeUpNeo")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("Wake up, Neo.")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text("Stay awake. Stay out of the way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
