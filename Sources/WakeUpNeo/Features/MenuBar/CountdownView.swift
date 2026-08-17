import SwiftUI
import WakeUpNeoCore

// MARK: - CountdownView

/// Shows the session's remaining time or indefinite/monitoring status.
///
/// Countdown is derived from `SleepManager.remainingTime`, which is itself
/// computed as `endDate.timeIntervalSinceNow` — never decremented —
/// so it cannot drift over time.
struct CountdownView: View {

    let manager: SleepManager

    /// Turns orange when fewer than 5 minutes remain, giving the user a
    /// calm, non-distracting heads-up without any flashing or pulsing.
    private var isExpiringSoon: Bool {
        manager.remainingTime > 0 && manager.remainingTime < 300
    }

    var body: some View {
        Group {
            switch manager.mode {
            case .off:
                EmptyView()

            case .indefinite:
                Label("Active indefinitely", systemImage: "infinity")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .timed:
                Text(formattedRemaining)
                    .font(.caption)
                    .foregroundStyle(isExpiringSoon ? Color.orange : .secondary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeInOut(duration: 0.3), value: manager.remainingTime)

            case .watchingDownloads(_, let activeCount):
                Label(
                    activeCount > 0 ? "\(activeCount) active \(activeCount == 1 ? "download" : "downloads")" : "Watching for downloads",
                    systemImage: "arrow.down.circle"
                )
                .font(.caption)
                .foregroundStyle(activeCount > 0 ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            case .waitingForFile(let url):
                if manager.isStabilizingFile {
                    Label(
                        "Stabilizing \(url.lastPathComponent)…",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                } else {
                    Label(
                        "Waiting for \(url.lastPathComponent)",
                        systemImage: "doc.badge.clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }
        }
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Formatting

    private var formattedRemaining: String {
        let total   = max(0, Int(manager.remainingTime))
        let hours   = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s remaining"
        } else {
            return "\(seconds)s remaining"
        }
    }

    private var accessibilityDescription: String {
        switch manager.mode {
        case .off:                         return ""
        case .indefinite:                  return "Session is active indefinitely"
        case .timed:                       return "Session time remaining"
        case .watchingDownloads:           return "Watching downloads in progress"
        case .waitingForFile:              return manager.isStabilizingFile ? "Target file is stabilizing" : "Waiting for target file"
        }
    }

    private var accessibilityValue: String {
        switch manager.mode {
        case .off:                         return ""
        case .indefinite:                  return "No time limit"
        case .timed:                       return formattedRemaining
        case .watchingDownloads(_, let count): return count > 0 ? "\(count) active \(count == 1 ? "download" : "downloads")" : "Watching for downloads"
        case .waitingForFile(let url):     return manager.isStabilizingFile ? "Stabilizing \(url.lastPathComponent)" : "Waiting for \(url.lastPathComponent)"
        }
    }
}
