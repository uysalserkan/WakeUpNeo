import AppKit
import Foundation
import Observation
import OSLog
import WakeUpNeoCore

// MARK: - UpdateManager

/// Central state manager for GitHub release checking and software updates.
@Observable
@MainActor
public final class UpdateManager {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "UpdateManager")

    // MARK: - Published Observable State

    public private(set) var isChecking: Bool = false
    public private(set) var updateAvailable: GitHubRelease? = nil
    public private(set) var lastCheckedDate: Date? = nil
    public private(set) var lastError: String? = nil
    public private(set) var hasChecked: Bool = false

    // MARK: - Dependencies & Configuration

    public let service: UpdateCheckerService

    public var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.5"
    }

    public var currentBuildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    public var isUpToDate: Bool {
        hasChecked && updateAvailable == nil && lastError == nil
    }

    // MARK: - Init

    public init(service: UpdateCheckerService = UpdateCheckerService()) {
        self.service = service
        let timestamp = UserDefaults.standard.double(forKey: AppSettingsKeys.lastUpdateCheckTimestamp)
        if timestamp > 0 {
            self.lastCheckedDate = Date(timeIntervalSince1970: timestamp)
        }
    }

    // MARK: - Actions

    /// Checks GitHub for newer releases.
    /// - Parameters:
    ///   - manual: Whether this check was explicitly triggered by user action (e.g. clicking "Check Now").
    ///   - notificationService: Optional service to deliver a system notification if a newer version is found during automatic checks.
    public func checkForUpdates(
        manual: Bool = false,
        notificationService: NotificationService? = nil
    ) async {
        guard !isChecking else { return }

        isChecking = true
        lastError = nil

        let version = currentVersionString
        logger.info("Checking for updates against current version: \(version) (manual: \(manual))")

        do {
            let result = try await service.checkForUpdates(currentVersionString: version)
            switch result {
            case .updateAvailable(let release, _):
                self.updateAvailable = release
                logger.info("Update found: \(release.tagName)")
                if !manual {
                    notificationService?.sendUpdateAvailableNotification(release: release)
                }
            case .upToDate:
                self.updateAvailable = nil
                logger.info("WakeUpNeo is up to date.")
            }

            let now = Date()
            self.lastCheckedDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: AppSettingsKeys.lastUpdateCheckTimestamp)
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            // Only populate visible error string on manual check so background checks stay silent on offline
            if manual {
                self.lastError = error.localizedDescription
            }
        }

        self.hasChecked = true
        self.isChecking = false
    }

    /// Clears any cached error state.
    public func clearError() {
        lastError = nil
    }

    /// Opens the release page in the default web browser.
    public func openReleasePage(for release: GitHubRelease? = nil) {
        guard let targetRelease = release ?? updateAvailable else {
            if let repoURL = URL(string: "https://github.com/\(service.owner)/\(service.repo)/releases") {
                NSWorkspace.shared.open(repoURL)
            }
            return
        }
        NSWorkspace.shared.open(targetRelease.htmlURL)
    }

    /// Opens the preferred binary download URL (DMG, Zip, or release page) in the browser.
    public func openDownloadLink(for release: GitHubRelease? = nil) {
        guard let targetRelease = release ?? updateAvailable else {
            openReleasePage()
            return
        }
        NSWorkspace.shared.open(targetRelease.preferredDownloadURL)
    }
}
