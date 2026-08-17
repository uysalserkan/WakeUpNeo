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

// MARK: - AdversarialM2TransitionsAndNotificationsTests
//
// Rigorous empirical stress-testing by challenger_m2_2:
// 1. SleepMode state machine transitions across all 5 modes in specific order
//    (timed -> watching downloads -> waiting for file -> indefinite -> off)
// 2. NotificationCenter event dispatch invariants:
//    - Completion notifications (.wakeUpNeoDownloadsCompleted, .wakeUpNeoFileDetected, .wakeUpNeoSessionExpired)
//    - Manual cancellation never fires completion notifications
//    - Mode switching never fires false completion notifications
//    - Notification object payload exact equality (URL objects)
//    - Stale / delayed background callbacks discarded safely
// 3. Dynamic preventSystemSleep / keepDisplayAwake toggles during active watch mode:
//    - Dynamic assertions toggled when watching downloads
//    - Dynamic assertions toggled when waiting for file
//    - Rapid stress toggling preserving internal consistency
// 4. Real filesystem watcher end-to-end multi-mode transition and completion

@MainActor
final class AdversarialM2TransitionsAndNotificationsTests: XCTestCase {

    private var systemMock: MockSleepService!
    private var displayMock: MockSleepService!
    private var composite: CompositeSleepService!
    private var watcherMock: MockFileWatchingService!
    private var manager: SleepManager!
    private var tempDir: TestTempDirectory!

    override func setUp() async throws {
        try await super.setUp()
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
        tempDir = try TestTempDirectory(prefix: "AdversarialM2TransitionsAndNotificationsTests")
    }

    override func tearDown() async throws {
        manager.stop()
        tempDir.cleanup()
        try await super.tearDown()
    }

    // MARK: - 1. Mode Switching Transitions

    /// Stress tests the explicit sequence: timed -> watching downloads -> waiting for file -> indefinite -> off
    func testExplicitModeSwitchingSequence() async throws {
        let downloadDir = try tempDir.createDirectory(named: "DownloadsDir")
        let targetFile = tempDir.url.appendingPathComponent("output.bin")

        // 1. Start timed session
        manager.start(for: 3600)
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isTimed)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertEqual(systemMock.startCallCount, 1)
        XCTAssertEqual(systemMock.stopCallCount, 0)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 0)

        // 2. Transition: timed -> watching downloads
        manager.startWatchingDownloads(directory: downloadDir)
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(manager.mode.watchedDirectory, downloadDir)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertEqual(systemMock.startCallCount, 2, "Must restart power assertion for new mode")
        XCTAssertEqual(systemMock.stopCallCount, 1, "Must release prior session power assertion")
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 1)
        XCTAssertEqual(manager.remainingTime, 0, "Remaining time must be reset")

        // 3. Transition: watching downloads -> waiting for file
        manager.startWaitingForFile(at: targetFile, stabilizationDuration: 1.0)
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isWaitingForFile)
        XCTAssertEqual(manager.mode.targetFileURL, targetFile)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertEqual(systemMock.startCallCount, 3)
        XCTAssertEqual(systemMock.stopCallCount, 2)
        XCTAssertEqual(watcherMock.stopCallCount, 2, "Stop called on transition from downloads")
        XCTAssertEqual(watcherMock.waitForFileCallCount, 1)

        // 4. Transition: waiting for file -> indefinite
        manager.startIndefinitely()
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isIndefinite)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertEqual(systemMock.startCallCount, 4)
        XCTAssertEqual(systemMock.stopCallCount, 3)
        XCTAssertEqual(watcherMock.stopCallCount, 3, "Stop called on transition from file waiting")

        // 5. Transition: indefinite -> off
        manager.stop()
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertEqual(systemMock.startCallCount, 4)
        XCTAssertEqual(systemMock.stopCallCount, 4, "Assertions balanced (started == stopped)")
    }

    /// High-iteration mode switching stress test to verify zero orphaned states or assertion leaks.
    func testRapidCyclicModeSwitchingStress() {
        let downloadDir = tempDir.url
        let targetFile = tempDir.url.appendingPathComponent("target.dat")

        let iterations = 25
        for i in 1...iterations {
            // Mode 1: Timed
            manager.start(for: TimeInterval(i * 10))
            XCTAssertTrue(manager.mode.isTimed)
            XCTAssertTrue(systemMock.isRunning)

            // Mode 2: Watching Downloads
            manager.startWatchingDownloads(directory: downloadDir)
            XCTAssertTrue(manager.mode.isWatchingDownloads)
            XCTAssertTrue(systemMock.isRunning)

            // Mode 3: Waiting for File
            manager.startWaitingForFile(at: targetFile)
            XCTAssertTrue(manager.mode.isWaitingForFile)
            XCTAssertTrue(systemMock.isRunning)

            // Mode 4: Indefinite
            manager.startIndefinitely()
            XCTAssertTrue(manager.mode.isIndefinite)
            XCTAssertTrue(systemMock.isRunning)

            // Mode 5: Off
            manager.stop()
            XCTAssertTrue(manager.mode.isOff)
            XCTAssertFalse(systemMock.isRunning)
        }

        // Each iteration runs 4 starts and 4 implicit stops + 1 explicit stop
        XCTAssertEqual(systemMock.startCallCount, iterations * 4)
        XCTAssertEqual(systemMock.stopCallCount, iterations * 4)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, iterations)
        XCTAssertEqual(watcherMock.waitForFileCallCount, iterations)
        XCTAssertFalse(manager.isActive)
        XCTAssertNil(manager.lastError)
    }

    // MARK: - 2. NotificationCenter Event Dispatches (Completion vs Cancellation)

    func testNotificationCenterDispatchesOnDownloadsCompletion() async throws {
        let downloadDir = try tempDir.createDirectory(named: "DownloadsTest")

        let receivedNotificationObject = SafeBox<URL?>(nil)
        let notificationReceived = expectation(description: "Downloads completed notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: .main
        ) { notification in
            receivedNotificationObject.set(notification.object as? URL)
            notificationReceived.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.startWatchingDownloads(directory: downloadDir)
        watcherMock.simulateDownloadComplete()

        await fulfillment(of: [notificationReceived], timeout: 2.0)
        XCTAssertEqual(receivedNotificationObject.get, downloadDir)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(manager.isActive)
    }

    func testNotificationCenterDispatchesOnFileDetected() async throws {
        let targetFile = tempDir.url.appendingPathComponent("ready.pdf")

        let receivedNotificationObject = SafeBox<URL?>(nil)
        let notificationReceived = expectation(description: "File detected notification received")

        let observer = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: .main
        ) { notification in
            receivedNotificationObject.set(notification.object as? URL)
            notificationReceived.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.startWaitingForFile(at: targetFile)
        watcherMock.simulateTargetFileComplete()

        await fulfillment(of: [notificationReceived], timeout: 2.0)
        XCTAssertEqual(receivedNotificationObject.get, targetFile)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(manager.isActive)
    }

    func testManualCancellationDoesNotDispatchCompletionNotifications() async throws {
        let downloadDir = tempDir.url
        let targetFile = tempDir.url.appendingPathComponent("test.zip")

        let unexpectedNotifications = SafeBox<[Notification.Name]>([])
        let observer1 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: .main
        ) { _ in
            unexpectedNotifications.set(unexpectedNotifications.get + [.wakeUpNeoDownloadsCompleted])
        }

        let observer2 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: .main
        ) { _ in
            unexpectedNotifications.set(unexpectedNotifications.get + [.wakeUpNeoFileDetected])
        }

        let observer3 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoSessionExpired,
            object: nil,
            queue: .main
        ) { _ in
            unexpectedNotifications.set(unexpectedNotifications.get + [.wakeUpNeoSessionExpired])
        }

        defer {
            NotificationCenter.default.removeObserver(observer1)
            NotificationCenter.default.removeObserver(observer2)
            NotificationCenter.default.removeObserver(observer3)
        }

        // Test 1: Stop watching downloads manually
        manager.startWatchingDownloads(directory: downloadDir)
        manager.stop()

        // Test 2: Stop waiting for file manually
        manager.startWaitingForFile(at: targetFile)
        manager.stop()

        // Test 3: Stop timed session manually
        manager.start(for: 100)
        manager.stop()

        // Test 4: Stop indefinite session manually
        manager.startIndefinitely()
        manager.stop()

        // Wait to ensure no asynchronous notification leaks
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(
            unexpectedNotifications.get.isEmpty,
            "Manual stop() must never post completion notifications! Received: \(unexpectedNotifications.get)"
        )
    }

    func testModeSwitchDoesNotDispatchCompletionNotifications() async throws {
        let downloadDir = tempDir.url
        let targetFile = tempDir.url.appendingPathComponent("test.zip")

        let receivedNotifications = SafeBox<[Notification.Name]>([])
        let observer1 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: .main
        ) { _ in
            receivedNotifications.set(receivedNotifications.get + [.wakeUpNeoDownloadsCompleted])
        }

        let observer2 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: .main
        ) { _ in
            receivedNotifications.set(receivedNotifications.get + [.wakeUpNeoFileDetected])
        }

        defer {
            NotificationCenter.default.removeObserver(observer1)
            NotificationCenter.default.removeObserver(observer2)
        }

        // Switch from watching downloads to timed session
        manager.startWatchingDownloads(directory: downloadDir)
        manager.start(for: 3600)

        // Switch from waiting for file to indefinite
        manager.startWaitingForFile(at: targetFile)
        manager.startIndefinitely()

        manager.stop()

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(
            receivedNotifications.get.isEmpty,
            "Mode switches must not trigger completion notifications. Received: \(receivedNotifications.get)"
        )
    }

    func testStaleCallbacksAfterStopAreSafelyIgnored() async throws {
        let downloadDir = tempDir.url
        let targetFile = tempDir.url.appendingPathComponent("target.dat")

        let receivedNotifications = SafeBox<[Notification.Name]>([])
        let observer1 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: .main
        ) { _ in
            receivedNotifications.set(receivedNotifications.get + [.wakeUpNeoDownloadsCompleted])
        }

        let observer2 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: .main
        ) { _ in
            receivedNotifications.set(receivedNotifications.get + [.wakeUpNeoFileDetected])
        }

        defer {
            NotificationCenter.default.removeObserver(observer1)
            NotificationCenter.default.removeObserver(observer2)
        }

        // 1. Start downloads, then stop
        manager.startWatchingDownloads(directory: downloadDir)
        manager.stop()

        // Simulate stale callbacks arriving from background threads after stop
        watcherMock.simulateDownloadUpdate(FileWatcherDownloadState(directory: downloadDir, activeDownloads: ["orphan.part"]))
        watcherMock.simulateDownloadComplete()

        XCTAssertTrue(manager.mode.isOff)
        XCTAssertTrue(manager.activeDownloads.isEmpty, "Stale update should not modify activeDownloads when off")

        // 2. Start waiting for file, then switch to timed
        manager.startWaitingForFile(at: targetFile)
        manager.start(for: 3600)

        // Simulate stale target file complete callback
        watcherMock.simulateTargetFileUpdate(FileWatcherTargetFileState(targetPath: targetFile, exists: true, isStabilizing: true, currentSize: 100))
        watcherMock.simulateTargetFileComplete()

        XCTAssertTrue(manager.mode.isTimed, "Stale complete should not change timed mode to off")
        XCTAssertFalse(manager.isStabilizingFile)

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(
            receivedNotifications.get.isEmpty,
            "Stale watcher callbacks must be discarded by guard checks! Received: \(receivedNotifications.get)"
        )
    }

    // MARK: - 3. Dynamic preventSystemSleep / keepDisplayAwake Toggles

    func testDynamicAssertionTogglesDuringWatchingDownloads() {
        let downloadDir = tempDir.url
        manager.startWatchingDownloads(directory: downloadDir)

        // Default state: preventSystemSleep = true, keepDisplayAwake = false
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 1)

        // 1. Enable keepDisplayAwake dynamically
        manager.keepDisplayAwake = true

        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertTrue(systemMock.isRunning, "System assertion stays running")
        XCTAssertTrue(displayMock.isRunning, "Display assertion should now be engaged")
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 2)

        // 2. Disable preventSystemSleep dynamically (keepDisplayAwake still true)
        manager.preventSystemSleep = false

        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertFalse(systemMock.isRunning, "System assertion should be released")
        XCTAssertTrue(displayMock.isRunning, "Display assertion stays running")
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 3)

        // 3. Disable both
        manager.keepDisplayAwake = false

        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 4)

        // 4. Re-enable preventSystemSleep
        manager.preventSystemSleep = true

        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 5)

        // 5. Final stop
        manager.stop()
        XCTAssertFalse(systemMock.isRunning, "System assertions released on stop")
        XCTAssertFalse(displayMock.isRunning, "Display assertions released on stop")
        XCTAssertTrue(manager.mode.isOff)
    }

    func testDynamicAssertionTogglesDuringWaitingForFile() {
        let targetFile = tempDir.url.appendingPathComponent("build.pkg")
        manager.startWaitingForFile(at: targetFile)

        XCTAssertTrue(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertEqual(watcherMock.waitForFileCallCount, 1)

        // Dynamic toggle display awake
        manager.keepDisplayAwake = true
        XCTAssertTrue(manager.mode.isWaitingForFile)
        XCTAssertEqual(manager.mode.targetFileURL, targetFile)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertTrue(displayMock.isRunning)
        XCTAssertEqual(watcherMock.waitForFileCallCount, 2, "Watcher restarts for active target file")

        // Dynamic toggle same value should be no-op
        manager.keepDisplayAwake = true
        XCTAssertEqual(watcherMock.waitForFileCallCount, 2, "Same value assignment must be no-op")

        manager.stop()
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertTrue(manager.mode.isOff)
    }

    func testRapidAssertionToggleStress() {
        let downloadDir = tempDir.url
        manager.startWatchingDownloads(directory: downloadDir)

        // Toggle properties rapidly 30 times
        for i in 0..<30 {
            manager.preventSystemSleep = (i % 2 == 0)
            manager.keepDisplayAwake = (i % 3 == 0)
        }

        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(manager.mode.watchedDirectory, downloadDir)

        manager.stop()
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
    }

    // MARK: - 4. Real Filesystem Watcher E2E Lifecycle & Mode Switching

    func testRealWatcherEndToEndModeSwitchAndCompletion() async throws {
        let realWatcher = DefaultFileWatcherService()
        let realManager = SleepManager(
            compositeService: composite,
            fileWatcherService: realWatcher
        )

        let targetDir = try tempDir.createDirectory(named: "RealDownloads")

        // 1. Create a download file
        let downloadFile = targetDir.appendingPathComponent("large_dataset.part")
        try Data("chunk 1".utf8).write(to: downloadFile)

        realManager.startWatchingDownloads(directory: targetDir)
        XCTAssertTrue(realManager.isActive)
        XCTAssertEqual(realManager.activeDownloads, ["large_dataset.part"])

        // 2. Switch to waiting for file in root temp directory
        let targetFile = tempDir.url.appendingPathComponent("complete_signal.ready")
        realManager.startWaitingForFile(at: targetFile, stabilizationDuration: 0.5)

        XCTAssertTrue(realManager.isActive)
        XCTAssertTrue(realManager.mode.isWaitingForFile)
        XCTAssertTrue(realManager.activeDownloads.isEmpty)

        // 3. Create the target file to satisfy the condition
        let fileDetectedExpectation = expectation(
            forNotification: .wakeUpNeoFileDetected,
            object: nil,
            notificationCenter: .default
        )

        try tempDir.createFile(named: "complete_signal.ready", text: "ready signal")

        await fulfillment(of: [fileDetectedExpectation], timeout: 4.0)

        XCTAssertFalse(realManager.isActive)
        XCTAssertTrue(realManager.mode.isOff)
        XCTAssertFalse(systemMock.isRunning)
    }
}
