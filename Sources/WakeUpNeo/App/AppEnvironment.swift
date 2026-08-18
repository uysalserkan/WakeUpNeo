import Foundation
import SwiftUI
import WakeUpNeoCore

// MARK: - AppEnvironment

/// Central dependency container. Assembled once at app startup.
///
/// Owns the `SleepManager` (the single source of truth for sleep state),
/// the `NotificationService`, and the `LaunchAtLoginService`.
/// Wires them together so neither the views nor the services know about
/// each other directly.
@Observable
@MainActor
final class AppEnvironment {

    // MARK: - Dependencies (accessible by views via @Environment)

    let sleepManager:         SleepManager
    let notificationService:  NotificationService
    let launchAtLoginService: LaunchAtLoginService
    let updateManager:        UpdateManager

    // MARK: - Private State

    @ObservationIgnored
    nonisolated(unsafe) private var observerTokens: [NSObjectProtocol] = []

    // MARK: - Init

    init(
        sleepManager: SleepManager? = nil,
        notificationService: NotificationService = NotificationService(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(),
        updateManager: UpdateManager? = nil
    ) {
        self.updateManager = updateManager ?? UpdateManager()
        if let customManager = sleepManager {
            self.sleepManager = customManager
        } else {
            // Build the composite power service using IOKit assertions,
            // which allow independent system-sleep and display-sleep control.
            let systemService = IOKitSleepService(
                assertionType: .preventIdleSystemSleep,
                reason: "WakeUpNeo: Preventing idle system sleep"
            )
            let displayService = IOKitSleepService(
                assertionType: .preventIdleDisplaySleep,
                reason: "WakeUpNeo: Preventing idle display sleep"
            )
            let lidService = IOKitSleepService(
                assertionType: .preventSystemSleep,
                reason: "WakeUpNeo: Preventing lid-close sleep"
            )
            let composite = CompositeSleepService(
                systemSleepService:  systemService,
                displaySleepService: displayService,
                lidSleepService:     lidService
            )
            self.sleepManager = SleepManager(compositeService: composite)
        }

        self.notificationService  = notificationService
        self.launchAtLoginService = launchAtLoginService

        // Restore persisted power settings into the manager
        let settings = AppSettings.load()
        self.sleepManager.preventSystemSleep = settings.preventSystemSleep
        self.sleepManager.keepDisplayAwake   = settings.keepDisplayAwake
        self.sleepManager.preventLidSleep    = settings.preventLidSleep

        // Request notification permission (no-op if already decided)
        Task {
            await self.notificationService.requestAuthorization()
        }

        // Check for updates in the background if automatic checking is enabled
        if settings.checkForUpdatesAutomatically {
            Task {
                await self.updateManager.checkForUpdates(manual: false, notificationService: self.notificationService)
            }
        }

        setupObservers()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        // 1. Timed session expired
        let expiredToken = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoSessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSessionExpired()
            }
        }
        observerTokens.append(expiredToken)

        // 2. Active downloads completed
        let downloadsToken = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let directory = notification.object as? URL
            Task { @MainActor [weak self] in
                self?.handleDownloadsCompleted(directory: directory)
            }
        }
        observerTokens.append(downloadsToken)

        // 3. Monitored target file detected & stabilized
        let fileToken = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let targetURL = notification.object as? URL else { return }
            Task { @MainActor [weak self] in
                self?.handleFileDetected(targetURL: targetURL)
            }
        }
        observerTokens.append(fileToken)

        // 4. Monitored application/process terminated
        let processToken = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoProcessTerminated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.object as? MonitoredProcessInfo else { return }
            Task { @MainActor [weak self] in
                self?.handleProcessTerminated(info: info)
            }
        }
        observerTokens.append(processToken)
    }

    // MARK: - Notification Handlers

    @MainActor
    private func handleSessionExpired() {
        let settings = AppSettings.load()
        guard settings.notifyOnSessionEnd else { return }
        notificationService.sendSessionEndedNotification()
    }

    @MainActor
    private func handleDownloadsCompleted(directory: URL?) {
        let settings = AppSettings.load()
        guard settings.notifyOnDownloadsComplete else { return }
        notificationService.sendDownloadsCompletedNotification(directory: directory)
    }

    @MainActor
    private func handleFileDetected(targetURL: URL) {
        let settings = AppSettings.load()
        guard settings.notifyOnFileDetected else { return }
        notificationService.sendFileDetectedNotification(targetURL: targetURL)
    }

    @MainActor
    private func handleProcessTerminated(info: MonitoredProcessInfo) {
        let settings = AppSettings.load()
        guard settings.notifyOnProcessTerminated else { return }
        notificationService.sendProcessTerminatedNotification(processName: info.name, pid: info.pid)
    }
}
