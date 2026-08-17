import XCTest
@testable import WakeUpNeoCore

private final class SafeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    var get: T {
        lock.withLock { value }
    }

    func set(_ newValue: T) {
        lock.withLock { value = newValue }
    }
}

// MARK: - AdversarialM2ChallengeTests
//
// Empirical Challenger stress tests for Milestone 2:
// - Repeated rapid starts and stops (single and cross-mode)
// - Starting watch downloads with 0 downloads vs >0 downloads
// - Assertions held during downloads and released immediately on completion
// - Startup error assertion rollback (system, display, and watcher failures)
// - Dynamic preventSystemSleep / keepDisplayAwake toggling during active monitoring
// - Mode switching and countdown cancellation
// - Stale callback immunity after cancellation
// - Real filesystem integration stress tests with DefaultFileWatcherService

@MainActor
final class AdversarialM2ChallengeTests: XCTestCase {

    private var systemMock: MockSleepService!
    private var displayMock: MockSleepService!
    private var composite: CompositeSleepService!
    private var watcherMock: MockFileWatchingService!
    private var manager: SleepManager!
    private var tempDir: TestTempDirectory!

    override func setUp() {
        super.setUp()
        systemMock = MockSleepService()
        displayMock = MockSleepService()
        composite = CompositeSleepService(
            systemSleepService: systemMock,
            displaySleepService: displayMock
        )
        watcherMock = MockFileWatchingService()
        manager = SleepManager(
            compositeService: composite,
            fileWatcherService: watcherMock
        )
        tempDir = try! TestTempDirectory(prefix: "AdversarialM2ChallengeTests")
    }

    override func tearDown() {
        manager?.stop()
        tempDir?.cleanup()
        super.tearDown()
    }

    // MARK: - 1. Repeated Rapid Starts and Stops Stress

    func testRapidStartStopSleepManagerCycleStress() {
        let iterations = 50
        for i in 1...iterations {
            manager.startWatchingDownloads(directory: tempDir.url)
            XCTAssertTrue(manager.isActive, "Session must be active on start (iteration \(i))")
            XCTAssertTrue(systemMock.isRunning, "System assertion must be held (iteration \(i))")
            XCTAssertEqual(watcherMock.watchDownloadsCallCount, i)

            manager.stop()
            XCTAssertFalse(manager.isActive, "Session must be inactive on stop (iteration \(i))")
            XCTAssertFalse(systemMock.isRunning, "System assertion must be released (iteration \(i))")
            XCTAssertFalse(watcherMock.isWatching, "Watcher must not be watching (iteration \(i))")
            XCTAssertEqual(watcherMock.stopCallCount, i)
        }

        // Final sanity check: 0 assertions held, clean state
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertEqual(manager.activeDownloads, [])
        XCTAssertFalse(manager.isStabilizingFile)
        XCTAssertNil(manager.lastError)
    }

    func testRapidStartStopWithMultipleModes() {
        let modes: [(Int) -> Void] = [
            { _ in self.manager.startIndefinitely() },
            { i in self.manager.start(for: TimeInterval(100 + i)) },
            { _ in self.manager.startWatchingDownloads(directory: self.tempDir.url) },
            { i in
                let target = self.tempDir.url.appendingPathComponent("file_\(i).pkg")
                self.manager.startWaitingForFile(at: target)
            }
        ]

        for i in 0..<40 {
            let startAction = modes[i % modes.count]
            startAction(i)
            XCTAssertTrue(manager.isActive)
            XCTAssertTrue(systemMock.isRunning)

            if i % 3 == 0 {
                // Occasional mid-cycle stop
                manager.stop()
                XCTAssertFalse(manager.isActive)
                XCTAssertFalse(systemMock.isRunning)
            }
        }

        manager.stop()
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertFalse(watcherMock.isWatching)
    }

    // MARK: - 2. Starting Watch Downloads with 0 vs >0 Downloads

    func testZeroDownloadsInitialWatchStateHoldsAssertionsAndWaits() async throws {
        // Directory has 0 downloads initially
        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(systemMock.isRunning, "Assertions MUST be held while watching empty directory for incoming downloads")
        XCTAssertEqual(manager.mode, .watchingDownloads(directory: tempDir.url, activeFilesCount: 0))
        XCTAssertTrue(manager.activeDownloads.isEmpty)

        // Incoming downloads arrive
        let stateWithDownloads = FileWatcherDownloadState(
            directory: tempDir.url,
            activeDownloads: ["installer.pkg.crdownload", "archive.zip.part"]
        )
        watcherMock.simulateDownloadUpdate(stateWithDownloads)

        XCTAssertEqual(manager.activeDownloads, ["installer.pkg.crdownload", "archive.zip.part"])
        XCTAssertEqual(manager.mode, .watchingDownloads(directory: tempDir.url, activeFilesCount: 2))
        XCTAssertTrue(systemMock.isRunning)

        // All downloads complete
        let notificationExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        watcherMock.simulateDownloadComplete()

        await fulfillment(of: [notificationExpectation], timeout: 2.0)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning, "Assertions MUST be released immediately when downloads complete")
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    func testNonZeroDownloadsInitialWatchStateTracksFilesAndReleasesOnEmpty() async throws {
        // Pre-create 3 active download files in filesystem
        try tempDir.createFile(named: "video1.part", text: "part1")
        try tempDir.createFile(named: "video2.crdownload", text: "part2")
        try tempDir.createFile(named: "video3.download", text: "part3")

        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertEqual(manager.activeDownloads.count, 3)
        XCTAssertEqual(manager.mode.activeFilesCount, 3)

        // Simulate 1 download completing
        watcherMock.simulateDownloadUpdate(FileWatcherDownloadState(
            directory: tempDir.url,
            activeDownloads: ["video2.crdownload", "video3.download"]
        ))
        XCTAssertEqual(manager.activeDownloads.count, 2)
        XCTAssertTrue(systemMock.isRunning, "Assertions must remain held while 2 downloads remain")

        // Simulate 2nd download completing
        watcherMock.simulateDownloadUpdate(FileWatcherDownloadState(
            directory: tempDir.url,
            activeDownloads: ["video3.download"]
        ))
        XCTAssertEqual(manager.activeDownloads.count, 1)
        XCTAssertTrue(systemMock.isRunning, "Assertions must remain held while 1 download remains")

        // Final download completes
        let notificationExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        watcherMock.simulateDownloadComplete()

        await fulfillment(of: [notificationExpectation], timeout: 2.0)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning, "Assertion must be released when all downloads complete")
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    // MARK: - 3. Assertions Held During Downloads & Released Immediately on Completion

    func testBothSystemAndDisplayAssertionsHeldAndReleasedTogether() async throws {
        manager.keepDisplayAwake = true

        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertTrue(systemMock.isRunning, "System sleep assertion must be running")
        XCTAssertTrue(displayMock.isRunning, "Display sleep assertion must be running")

        let notificationExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        watcherMock.simulateDownloadComplete()

        await fulfillment(of: [notificationExpectation], timeout: 2.0)

        XCTAssertFalse(systemMock.isRunning, "System assertion must be released on completion")
        XCTAssertFalse(displayMock.isRunning, "Display assertion must be released on completion")
        XCTAssertTrue(manager.mode.isOff)
    }

    func testTargetFileAssertionsHeldDuringStabilizationAndReleasedOnCompletion() async throws {
        let targetFile = tempDir.url.appendingPathComponent("final_release.dmg")
        manager.keepDisplayAwake = true
        manager.startWaitingForFile(at: targetFile, stabilizationDuration: 2.0)

        XCTAssertTrue(systemMock.isRunning)
        XCTAssertTrue(displayMock.isRunning)
        XCTAssertFalse(manager.isStabilizingFile)

        // File appears and begins stabilizing
        watcherMock.simulateTargetFileUpdate(FileWatcherTargetFileState(
            targetPath: targetFile,
            exists: true,
            isStabilizing: true,
            currentSize: 1048576
        ))
        XCTAssertTrue(manager.isStabilizingFile)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertTrue(displayMock.isRunning)

        // Stabilization completes
        let notificationExpectation = expectation(
            forNotification: .wakeUpNeoFileDetected,
            object: nil,
            notificationCenter: .default
        )

        watcherMock.simulateTargetFileComplete()

        await fulfillment(of: [notificationExpectation], timeout: 2.0)
        XCTAssertFalse(manager.isStabilizingFile)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertTrue(manager.mode.isOff)
    }

    // MARK: - 4. Startup Error Assertion Rollback

    func testWatcherStartupFailureRollsBackSystemAndDisplayAssertions() {
        manager.keepDisplayAwake = true
        watcherMock.shouldThrowOnWatch = FileWatcherError.unreadablePath(tempDir.url)

        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning, "System assertion must be rolled back on watcher failure")
        XCTAssertFalse(displayMock.isRunning, "Display assertion must be rolled back on watcher failure")
        XCTAssertNotNil(manager.lastError)
    }

    func testTargetFileWatcherStartupFailureRollsBackAssertions() {
        let targetFile = tempDir.url.appendingPathComponent("nonexistent/test.bin")
        watcherMock.shouldThrowOnWatch = FileWatcherError.directoryNotFound(targetFile.deletingLastPathComponent())

        manager.startWaitingForFile(at: targetFile)

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning, "System assertion must be rolled back")
        XCTAssertNotNil(manager.lastError)
    }

    func testDisplaySleepStartupFailureRollsBackSystemAssertion() {
        manager.keepDisplayAwake = true
        displayMock.shouldThrowOnStart = true

        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning, "System assertion must be rolled back if display sleep assertion fails to start")
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 0, "Watcher must NOT be started if power assertions fail")
        XCTAssertNotNil(manager.lastError)
    }

    func testSystemSleepStartupFailureAbortsCleanly() {
        systemMock.shouldThrowOnStart = true

        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 0, "Watcher must NOT be started if system sleep fails")
        XCTAssertNotNil(manager.lastError)
    }

    // MARK: - 5. Stale Callbacks Immunity

    func testStaleCallbacksAfterStopAreIgnored() async throws {
        let downloadDir = tempDir.url
        let targetFile = tempDir.url.appendingPathComponent("out.dat")

        let unexpectedNotifications = SafeBox<[Notification.Name]>([])
        let obs1 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: .main
        ) { _ in unexpectedNotifications.set(unexpectedNotifications.get + [.wakeUpNeoDownloadsCompleted]) }
        let obs2 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: .main
        ) { _ in unexpectedNotifications.set(unexpectedNotifications.get + [.wakeUpNeoFileDetected]) }
        defer {
            NotificationCenter.default.removeObserver(obs1)
            NotificationCenter.default.removeObserver(obs2)
        }

        // 1. Start downloads, then stop
        manager.startWatchingDownloads(directory: downloadDir)
        manager.stop()

        // Simulate stale callbacks arriving after stop
        watcherMock.simulateDownloadUpdate(FileWatcherDownloadState(directory: downloadDir, activeDownloads: ["orphan.part"]))
        watcherMock.simulateDownloadComplete()

        XCTAssertTrue(manager.mode.isOff)
        XCTAssertTrue(manager.activeDownloads.isEmpty)

        // 2. Start waiting for file, then switch to timed
        manager.startWaitingForFile(at: targetFile)
        manager.start(for: 3600)

        // Simulate stale target file complete callback
        watcherMock.simulateTargetFileUpdate(FileWatcherTargetFileState(targetPath: targetFile, exists: true, isStabilizing: true, currentSize: 100))
        watcherMock.simulateTargetFileComplete()

        XCTAssertTrue(manager.mode.isTimed, "Stale complete should not change timed mode to off")
        XCTAssertFalse(manager.isStabilizingFile)

        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(unexpectedNotifications.get.isEmpty, "Stale watcher callbacks must be discarded!")
    }

    // MARK: - 6. Dynamic Power Settings Toggling

    func testDynamicPowerTogglesDuringActiveSession() {
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 1)

        // Turn on keepDisplayAwake
        manager.keepDisplayAwake = true
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertTrue(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 2)
        XCTAssertTrue(manager.mode.isWatchingDownloads)

        // Turn off preventSystemSleep
        manager.preventSystemSleep = false
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertTrue(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 3)
        XCTAssertTrue(manager.mode.isWatchingDownloads)

        // Turn off keepDisplayAwake too (both off)
        manager.keepDisplayAwake = false
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 4)
        XCTAssertTrue(manager.mode.isWatchingDownloads)

        // Re-enable preventSystemSleep
        manager.preventSystemSleep = true
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 5)
        XCTAssertTrue(manager.mode.isWatchingDownloads)

        manager.stop()
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertTrue(manager.mode.isOff)
    }

    func testDynamicPowerTogglesWhenOffIsNoOp() {
        XCTAssertTrue(manager.mode.isOff)

        manager.preventSystemSleep = false
        manager.keepDisplayAwake = true
        manager.preventSystemSleep = true
        manager.keepDisplayAwake = false

        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 0)
    }

    // MARK: - 7. Mode Switching and Countdown Cancellation

    func testTimedCountdownCancelledWhenSwitchingToDownloadWatching() async throws {
        manager.start(for: 3600)
        XCTAssertTrue(manager.mode.isTimed)
        XCTAssertGreaterThan(manager.remainingTime, 0)

        // Switch directly to watching downloads
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(manager.remainingTime, 0, "Remaining time must reset to 0 on mode switch")

        // Wait a short tick to ensure countdown task is not firing into mode
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(manager.remainingTime, 0)
    }

    func testWatcherStoppedWhenSwitchingToIndefinite() {
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 1)

        manager.startIndefinitely()
        XCTAssertTrue(manager.mode.isIndefinite)
        XCTAssertEqual(watcherMock.stopCallCount, 1, "Watcher must be stopped when transitioning to indefinite")
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    func testWatcherStoppedWhenSwitchingBetweenDownloadsAndTargetFile() {
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(manager.mode.isWatchingDownloads)

        let target = tempDir.url.appendingPathComponent("output.bin")
        manager.startWaitingForFile(at: target)
        XCTAssertTrue(manager.mode.isWaitingForFile)
        XCTAssertEqual(watcherMock.stopCallCount, 1)
        XCTAssertEqual(watcherMock.waitForFileCallCount, 1)
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    // MARK: - 8. Real DefaultFileWatcherService + SleepManager Integration Stress

    func testRealFileWatcherBatchDownloadsLifecycle() async throws {
        let realWatcher = DefaultFileWatcherService()
        let realManager = SleepManager(
            compositeService: composite,
            fileWatcherService: realWatcher
        )

        // Create 3 active download files
        try tempDir.createFile(named: "batch_1.crdownload", text: "part1")
        try tempDir.createFile(named: "batch_2.part", text: "part2")
        try tempDir.createFile(named: "batch_3.download", text: "part3")

        realManager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(realManager.isActive)
        XCTAssertEqual(realManager.activeDownloads.count, 3)
        XCTAssertTrue(systemMock.isRunning)

        let completionExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        // Remove 2 downloads
        try tempDir.renameFile(from: "batch_1.crdownload", to: "batch_1.zip")
        try tempDir.renameFile(from: "batch_2.part", to: "batch_2.iso")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(realManager.isActive, "Real manager must remain active while 1 download is remaining")
        XCTAssertTrue(systemMock.isRunning)

        // Remove final download
        try tempDir.renameFile(from: "batch_3.download", to: "batch_3.dmg")

        await fulfillment(of: [completionExpectation], timeout: 4.0)

        XCTAssertFalse(realManager.isActive)
        XCTAssertTrue(realManager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning, "Power assertions must be released after real file watcher completes")
        XCTAssertTrue(realManager.activeDownloads.isEmpty)
    }

    func testRealFileWatcherTargetFileStabilizationWithSleepManager() async throws {
        let realWatcher = DefaultFileWatcherService()
        let realManager = SleepManager(
            compositeService: composite,
            fileWatcherService: realWatcher
        )

        let targetFile = tempDir.url.appendingPathComponent("stream_output.mp4")

        realManager.startWaitingForFile(at: targetFile, stabilizationDuration: 0.4)
        XCTAssertTrue(realManager.isActive)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertFalse(realManager.isStabilizingFile)

        let completionExpectation = expectation(
            forNotification: .wakeUpNeoFileDetected,
            object: nil,
            notificationCenter: .default
        )

        // Create target file
        try tempDir.createFile(named: "stream_output.mp4", text: "chunk1")

        // Wait for stabilization to complete
        await fulfillment(of: [completionExpectation], timeout: 4.0)

        XCTAssertFalse(realManager.isActive)
        XCTAssertTrue(realManager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(realManager.isStabilizingFile)
    }

    func testConcurrentMainActorStateTransitions() async throws {
        let iterations = 30
        for i in 0..<iterations {
            if i % 4 == 0 {
                manager.startIndefinitely()
            } else if i % 4 == 1 {
                manager.startWatchingDownloads(directory: tempDir.url)
            } else if i % 4 == 2 {
                let target = tempDir.url.appendingPathComponent("target_\(i).tmp")
                manager.startWaitingForFile(at: target)
            } else {
                manager.stop()
            }
        }
        manager.stop()

        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertFalse(watcherMock.isWatching)
    }
}
