import SwiftUI
import WakeUpNeoCore

// MARK: - UpdateBannerView

/// Notification banner displayed when a new version of WakeUpNeo is available on GitHub.
struct UpdateBannerView: View {

    let release: GitHubRelease
    let onOpenDownload: (GitHubRelease) -> Void

    var body: some View {
        Button {
            onOpenDownload(release)
        } label: {
            HStack(spacing: 8) {
                MenuRowIcon("arrow.triangle.2.circlepath.circle.fill", color: Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Update Available")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(release.displayTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("Update")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: NativeTheme.rowCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Update Available: \(release.displayTitle). Click to update.")
    }
}
