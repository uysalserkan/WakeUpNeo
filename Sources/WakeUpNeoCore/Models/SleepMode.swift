import Foundation

/// The current sleep-prevention state of the application.
///
/// This enum is the single source of truth for what mode WakeUpNeo is in.
/// The UI and services derive all their behaviour from this value.
public enum SleepMode: Equatable, Sendable {
    /// Sleep prevention is off. The system behaves normally.
    case off
    /// Sleep prevention is active with no time limit.
    case indefinite
    /// Sleep prevention is active until the given absolute date.
    case timed(until: Date)
    /// Sleep prevention is active while monitoring active downloads in a directory.
    case watchingDownloads(directory: URL, activeFilesCount: Int)
    /// Sleep prevention is active while waiting for a specific file to appear and stabilize.
    case waitingForFile(targetURL: URL)

    // MARK: - State Inspection

    public var isOff: Bool {
        guard case .off = self else { return false }
        return true
    }

    public var isActive: Bool { !isOff }

    public var isIndefinite: Bool {
        guard case .indefinite = self else { return false }
        return true
    }

    public var isTimed: Bool {
        guard case .timed = self else { return false }
        return true
    }

    public var isWatchingDownloads: Bool {
        guard case .watchingDownloads = self else { return false }
        return true
    }

    public var isWaitingForFile: Bool {
        guard case .waitingForFile = self else { return false }
        return true
    }

    public var isSmartWatching: Bool {
        isWatchingDownloads || isWaitingForFile
    }

    // MARK: - Associated Values

    /// The expiry date, if this is a timed session.
    public var endDate: Date? {
        guard case .timed(let date) = self else { return nil }
        return date
    }

    /// The watched directory, if this is a download watching session.
    public var watchedDirectory: URL? {
        guard case .watchingDownloads(let directory, _) = self else { return nil }
        return directory
    }

    /// The number of active downloading files currently observed.
    public var activeFilesCount: Int? {
        guard case .watchingDownloads(_, let count) = self else { return nil }
        return count
    }

    /// The target file URL, if this is a target file waiting session.
    public var targetFileURL: URL? {
        guard case .waitingForFile(let url) = self else { return nil }
        return url
    }

    // MARK: - Formatters & Display Labels

    /// Short label describing the current mode (e.g. for status headers or accessibility).
    public var statusTitle: String {
        switch self {
        case .off:
            return "Off"
        case .indefinite:
            return "Indefinite"
        case .timed:
            return "Timed"
        case .watchingDownloads(_, let count):
            return count > 0 ? "Downloading (\(count))" : "Watching Downloads"
        case .waitingForFile(let url):
            return "Waiting for \(url.lastPathComponent)"
        }
    }

    /// Full descriptive description of the current mode.
    public var statusDescription: String {
        switch self {
        case .off:
            return "Your Mac can sleep normally"
        case .indefinite:
            return "Sleep prevention is active indefinitely"
        case .timed(let date):
            return "Sleep prevention active until \(date.formatted(date: .omitted, time: .shortened))"
        case .watchingDownloads(let dir, let count):
            if count > 0 {
                return "\(count) active \(count == 1 ? "download" : "downloads") in \(dir.lastPathComponent)"
            } else {
                return "Watching for downloads in \(dir.lastPathComponent)"
            }
        case .waitingForFile(let url):
            return "Waiting for \(url.lastPathComponent) to appear and finish writing"
        }
    }
}
