import Foundation
import UserNotifications
import OSLog

/// Sends `UserNotifications` for session lifecycle events.
///
/// Notifications are configurable — callers should check the user's
/// preference before invoking these methods.
public final class NotificationService: Sendable {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "Notifications")

    public init() {}

    private var isNotificationCenterAvailable: Bool {
        // UNUserNotificationCenter requires a valid .app bundle host to initialize.
        // In command-line tools or xctest test runners, initializing UNUserNotificationCenter
        // causes an uncatchable Objective-C NSException.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              Bundle.main.bundleURL.pathExtension == "app" || Bundle.main.bundleURL.path.contains(".app/") else {
            return false
        }
        return true
    }

    // MARK: - Authorisation

    /// Request notification permission. Call once at app launch.
    public func requestAuthorization() async {
        guard isNotificationCenterAvailable else {
            logger.info("Notification authorisation skipped: bundle identifier is nil (e.g. test runner)")
            return
        }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            logger.info("Notification authorisation: \(granted ? "granted" : "denied")")
        } catch {
            logger.error("Notification authorisation error: \(error)")
        }
    }

    // MARK: - Session Ended

    /// "WakeUpNeo session finished. Your Mac can sleep normally again."
    public func sendSessionEndedNotification() {
        let content       = UNMutableNotificationContent()
        content.title     = "WakeUpNeo Session Ended"
        content.body      = "Your Mac can sleep normally again."
        content.sound     = .default

        schedule(content, identifier: "com.wakeupneo.sessionEnded.\(UUID().uuidString)")
    }

    // MARK: - Session Expiring Soon

    /// "WakeUpNeo session ends in N minute(s)."
    public func sendSessionExpiringSoonNotification(minutesRemaining: Int) {
        let content       = UNMutableNotificationContent()
        content.title     = "WakeUpNeo Session Ending Soon"
        content.body      = "Your WakeUpNeo session ends in \(minutesRemaining) \(minutesRemaining == 1 ? "minute" : "minutes")."
        content.sound     = nil

        // Replace any previous "expiring" notification rather than stacking
        schedule(content, identifier: "com.wakeupneo.sessionExpiring")
    }

    // MARK: - Downloads Completed

    /// "All downloads in <directory> have finished. Your Mac can sleep normally again."
    public func sendDownloadsCompletedNotification(directory: URL? = nil) {
        let content       = UNMutableNotificationContent()
        content.title     = "Downloads Completed"
        if let dir = directory {
            content.body  = "All downloads in '\(dir.lastPathComponent)' have finished. Your Mac can sleep normally again."
        } else {
            content.body  = "All downloads have finished. Your Mac can sleep normally again."
        }
        content.sound     = .default

        schedule(content, identifier: "com.wakeupneo.downloadsCompleted.\(UUID().uuidString)")
    }

    // MARK: - File Detected

    /// "Target file '<filename>' has appeared and stabilized. Your Mac can sleep normally again."
    public func sendFileDetectedNotification(targetURL: URL) {
        let content       = UNMutableNotificationContent()
        content.title     = "Target File Ready"
        content.body      = "Target file '\(targetURL.lastPathComponent)' has appeared and stabilized. Your Mac can sleep normally again."
        content.sound     = .default

        schedule(content, identifier: "com.wakeupneo.fileDetected.\(UUID().uuidString)")
    }

    // MARK: - Private

    private func schedule(_ content: UNNotificationContent, identifier: String) {
        guard isNotificationCenterAvailable else {
            logger.info("Notification scheduling skipped for '\(identifier)': bundle identifier is nil (e.g. test runner)")
            return
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to schedule notification '\(identifier)': \(error)")
            }
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted on the main thread when a timed session expires automatically.
    static let wakeUpNeoSessionExpired = Notification.Name("com.wakeupneo.sessionExpired")

    /// Posted on the main thread when active downloads have completed and sleep prevention is released.
    static let wakeUpNeoDownloadsCompleted = Notification.Name("com.wakeupneo.downloadsCompleted")

    /// Posted on the main thread when a monitored target file is detected & stabilized, and sleep prevention is released.
    static let wakeUpNeoFileDetected = Notification.Name("com.wakeupneo.fileDetected")
}
