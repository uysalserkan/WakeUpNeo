import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.wakeupneo.app", category: "SleepManager")

// MARK: - SleepManager

/// The central state owner for WakeUpNeo.
///
/// **All power-management operations go through this class.** The UI never
/// touches IOKit or `ProcessInfo` directly.
///
/// - Observation: Uses `@Observable` (Swift 5.9+, macOS 14+) so SwiftUI
///   views can subscribe to changes without `ObservableObject` overhead.
/// - Threading:   `@MainActor` — all mutations happen on the main thread.
///   The countdown `Task` publishes updates via `MainActor.run`.
@Observable
@MainActor
public final class SleepManager {

    // MARK: - Published State

    public private(set) var mode:              SleepMode    = .off
    public private(set) var remainingTime:     TimeInterval  = 0
    public private(set) var activeDownloads:   [String]      = []
    public private(set) var isStabilizingFile: Bool          = false
    public private(set) var lastError:         Error?        = nil

    public var isActive: Bool { !mode.isOff }

    // MARK: - Power Settings (affect active sessions immediately)

    /// When `true`, the system sleep assertion is active during a session.
    public var preventSystemSleep: Bool = true {
        didSet {
            guard oldValue != preventSystemSleep else { return }
            restartCurrentSession()
        }
    }

    /// When `true`, the display sleep assertion is also active during a session.
    public var keepDisplayAwake: Bool = false {
        didSet {
            guard oldValue != keepDisplayAwake else { return }
            restartCurrentSession()
        }
    }

    /// When `true`, the lid-close sleep assertion is active during a session.
    public var preventLidSleep: Bool = false {
        didSet {
            guard oldValue != preventLidSleep else { return }
            restartCurrentSession()
        }
    }

    // MARK: - Dependencies & Private State

    private let compositeService:   CompositeSleepService
    private let fileWatcherService: FileWatchingService
    private var countdownTask:      Task<Void, Never>?

    // MARK: - Init

    public init(
        compositeService: CompositeSleepService,
        fileWatcherService: FileWatchingService = DefaultFileWatcherService()
    ) {
        self.compositeService   = compositeService
        self.fileWatcherService = fileWatcherService
    }

    // MARK: - Public Interface: Timed & Indefinite

    /// Start a timed session that ends `duration` seconds from now.
    public func start(for duration: TimeInterval) {
        let endDate = Date.now.addingTimeInterval(duration)
        start(until: endDate)
    }

    /// Start a timed session that ends at the given absolute `Date`.
    public func start(until endDate: Date) {
        stop()
        do {
            try activateServices()
            mode              = .timed(until: endDate)
            remainingTime     = max(0, endDate.timeIntervalSinceNow)
            activeDownloads   = []
            isStabilizingFile = false
            lastError         = nil
            beginCountdown(until: endDate)
            logger.info("[Power] Session started (timed until \(endDate))")
        } catch {
            lastError = error
            logger.error("[Power] Failed to start timed session: \(error)")
        }
    }

    /// Start an indefinite session with no automatic expiry.
    public func startIndefinitely() {
        stop()
        do {
            try activateServices()
            mode              = .indefinite
            remainingTime     = 0
            activeDownloads   = []
            isStabilizingFile = false
            lastError         = nil
            logger.info("[Power] Indefinite session started")
        } catch {
            lastError = error
            logger.error("[Power] Failed to start indefinite session: \(error)")
        }
    }

    // MARK: - Public Interface: Smart Watchers

    /// Start watching a directory for active downloads.
    /// Sleep prevention will be held until all downloading files (.crdownload, .part, etc.) finish.
    public func startWatchingDownloads(
        directory: URL? = nil,
        customExtensions: Set<String>? = nil
    ) {
        stop()
        let targetDir = directory ?? AppSettings.defaultDownloadsURL
        let effectiveExtensions = DownloadPatternMatcher.effectiveExtensions(customExtensions: customExtensions)
        let initialActive = DownloadPatternMatcher.activeDownloads(in: targetDir, temporaryExtensions: effectiveExtensions)

        do {
            try activateServices()
            mode              = .watchingDownloads(directory: targetDir, activeFilesCount: initialActive.count)
            activeDownloads   = initialActive
            isStabilizingFile = false
            remainingTime     = 0
            lastError         = nil

            try fileWatcherService.watchDownloads(
                in: targetDir,
                temporaryExtensions: effectiveExtensions,
                onUpdate: { [weak self] state in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.handleDownloadsUpdate(state) }
                    } else {
                        Task { @MainActor [weak self] in
                            self?.handleDownloadsUpdate(state)
                        }
                    }
                },
                onComplete: { [weak self] in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.handleDownloadsComplete(directory: targetDir) }
                    } else {
                        Task { @MainActor [weak self] in
                            self?.handleDownloadsComplete(directory: targetDir)
                        }
                    }
                },
                onError: { [weak self] error in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.handleWatcherError(error) }
                    } else {
                        Task { @MainActor [weak self] in
                            self?.handleWatcherError(error)
                        }
                    }
                }
            )
            logger.info("[Power] Download watching session started for \(targetDir.path(percentEncoded: false))")
        } catch {
            // Rollback power assertions if watcher fails to start
            compositeService.stopAll()
            mode              = .off
            activeDownloads   = []
            isStabilizingFile = false
            lastError         = error
            logger.error("[Power] Failed to start download watching: \(error)")
        }
    }

    /// Start waiting for a specific file to be created and stabilize.
    /// Sleep prevention will be held until the file exists and is completely written.
    public func startWaitingForFile(
        at targetPath: URL,
        stabilizationDuration: TimeInterval = 2.0
    ) {
        stop()
        do {
            try activateServices()
            mode              = .waitingForFile(targetURL: targetPath)
            activeDownloads   = []
            isStabilizingFile = false
            remainingTime     = 0
            lastError         = nil

            try fileWatcherService.waitForFile(
                at: targetPath,
                stabilizationDuration: stabilizationDuration,
                onUpdate: { [weak self] state in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.handleTargetFileUpdate(state) }
                    } else {
                        Task { @MainActor [weak self] in
                            self?.handleTargetFileUpdate(state)
                        }
                    }
                },
                onComplete: { [weak self] in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.handleTargetFileComplete(targetURL: targetPath) }
                    } else {
                        Task { @MainActor [weak self] in
                            self?.handleTargetFileComplete(targetURL: targetPath)
                        }
                    }
                },
                onError: { [weak self] error in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.handleWatcherError(error) }
                    } else {
                        Task { @MainActor [weak self] in
                            self?.handleWatcherError(error)
                        }
                    }
                }
            )
            logger.info("[Power] Target file waiting session started for \(targetPath.path(percentEncoded: false))")
        } catch {
            compositeService.stopAll()
            mode              = .off
            activeDownloads   = []
            isStabilizingFile = false
            lastError         = error
            logger.error("[Power] Failed to start waiting for file: \(error)")
        }
    }

    // MARK: - Public Interface: Stop & Error Handling

    /// Stop any active session, stop watchers, and release all power assertions.
    /// Idempotent — safe to call when already stopped.
    public func stop() {
        guard !mode.isOff else { return }
        cancelCountdown()
        fileWatcherService.stop()
        compositeService.stopAll()
        mode              = .off
        remainingTime     = 0
        activeDownloads   = []
        isStabilizingFile = false
        logger.info("[Power] Session stopped")
    }

    /// Clear the last recorded error (e.g. after showing it in the UI).
    public func clearError() {
        lastError = nil
    }

    // MARK: - Private: Services

    private func activateServices() throws {
        if preventSystemSleep {
            try compositeService.startSystemSleep()
        }
        if keepDisplayAwake {
            try compositeService.startDisplaySleep()
        }
        if preventLidSleep {
            try compositeService.startLidSleep()
        }
    }

    /// Re-apply service settings while preserving the current session mode.
    private func restartCurrentSession() {
        guard isActive else { return }
        let snapshot = mode

        // Tear down fully first
        cancelCountdown()
        fileWatcherService.stop()
        compositeService.stopAll()
        mode = .off

        // Re-start with the same mode
        switch snapshot {
        case .off:
            break
        case .indefinite:
            startIndefinitely()
        case .timed(let endDate):
            if endDate > Date.now {
                start(until: endDate)
            }
        case .watchingDownloads(let directory, _):
            startWatchingDownloads(directory: directory)
        case .waitingForFile(let targetURL):
            startWaitingForFile(at: targetURL)
        }
    }

    // MARK: - Private: Countdown

    /// Starts a background task that updates `remainingTime` every second
    /// and triggers automatic expiry when `endDate` passes.
    ///
    /// Countdown is computed from the absolute `endDate`, not decremented,
    /// so it can never drift regardless of sleep/wake cycles.
    private func beginCountdown(until endDate: Date) {
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = endDate.timeIntervalSinceNow
                if remaining <= 0 {
                    await MainActor.run { [weak self] in self?.handleExpiration() }
                    return
                }
                await MainActor.run { [weak self] in
                    self?.remainingTime = remaining
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    // MARK: - Private: Watcher & Expiration Handlers

    @MainActor
    private func handleExpiration() {
        logger.info("[Power] Session ending (timer expired)")
        cancelCountdown()
        compositeService.stopAll()
        mode          = .off
        remainingTime = 0
        NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)
    }

    @MainActor
    private func handleDownloadsUpdate(_ state: FileWatcherDownloadState) {
        guard case .watchingDownloads(let dir, _) = mode, dir == state.directory else { return }
        activeDownloads = state.activeDownloads
        mode = .watchingDownloads(directory: dir, activeFilesCount: state.activeDownloads.count)
    }

    @MainActor
    private func handleDownloadsComplete(directory: URL) {
        guard case .watchingDownloads(let dir, _) = mode, dir == directory else { return }
        logger.info("[Power] All downloads finished in \(directory.path(percentEncoded: false)), auto-stopping")
        fileWatcherService.stop()
        compositeService.stopAll()
        mode              = .off
        remainingTime     = 0
        activeDownloads   = []
        isStabilizingFile = false
        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: directory)
    }

    @MainActor
    private func handleTargetFileUpdate(_ state: FileWatcherTargetFileState) {
        guard case .waitingForFile(let targetURL) = mode, targetURL == state.targetPath else { return }
        isStabilizingFile = state.isStabilizing
    }

    @MainActor
    private func handleTargetFileComplete(targetURL: URL) {
        guard case .waitingForFile(let target) = mode, target == targetURL else { return }
        logger.info("[Power] Target file appeared and stabilized at \(targetURL.path(percentEncoded: false)), auto-stopping")
        fileWatcherService.stop()
        compositeService.stopAll()
        mode              = .off
        remainingTime     = 0
        activeDownloads   = []
        isStabilizingFile = false
        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: targetURL)
    }

    @MainActor
    private func handleWatcherError(_ error: Error) {
        logger.error("[Power] File watcher error: \(error)")
        lastError = error
        stop()
    }
}
