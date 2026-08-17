import XCTest
@testable import WakeUpNeoCore

// MARK: - SleepManagerFileWatcherTests
//
// Comprehensive Tier 1-3 integration tests for SleepManager with FileWatchingService.
// Covers assertion lifecycles, mode switches, auto-completion, cancellations,
// rollback on startup errors, and dynamic power setting restarts.

@MainActor
final class SleepManagerFileWatcherTests: XCTestCase {

    var systemMock: MockSleepService!
    var displayMock: MockSleepService!
    var composite: CompositeSleepService!
    var watcherMock: MockFileWatchingService!
    var manager: SleepManager!
    var tempDir: TestTempDirectory!

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
        tempDir = try! TestTempDirectory(prefix: "SleepManagerFileWatcherTests")
    }

    override func tearDown() {
        manager?.stop()
        tempDir?.cleanup()
        super.tearDown()
    }

    // MARK: - Tier 1: Download Watching Lifecycle

    func testStartWatchingDownloadsActivatesAssertionsAndWatcher() {
        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(manager.mode.watchedDirectory, tempDir.url)
        XCTAssertEqual(systemMock.startCallCount, 1)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 1)
        XCTAssertEqual(watcherMock.lastWatchedDirectory, tempDir.url)
        XCTAssertNil(manager.lastError)
    }

    func testDownloadsUpdateUpdatesActiveDownloadsAndModeCount() {
        manager.startWatchingDownloads(directory: tempDir.url)

        let updateState = FileWatcherDownloadState(
            directory: tempDir.url,
            activeDownloads: ["archive.part", "video.crdownload"]
        )
        watcherMock.simulateDownloadUpdate(updateState)

        XCTAssertEqual(manager.activeDownloads, ["archive.part", "video.crdownload"])
        XCTAssertEqual(manager.mode.activeFilesCount, 2)
        XCTAssertEqual(manager.mode, .watchingDownloads(directory: tempDir.url, activeFilesCount: 2))
    }

    func testDownloadsCompletionAutoStopsSessionAndPostsNotification() async throws {
        manager.startWatchingDownloads(directory: tempDir.url)

        let notificationExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        watcherMock.simulateDownloadComplete()

        await fulfillment(of: [notificationExpectation], timeout: 2.0)
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertEqual(systemMock.stopCallCount, 1)
        XCTAssertEqual(watcherMock.stopCallCount, 1)
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    // MARK: - Tier 1: Target File Waiting Lifecycle

    func testStartWaitingForFileActivatesAssertionsAndWatcher() {
        let targetFile = tempDir.url.appendingPathComponent("build.iso")
        manager.startWaitingForFile(at: targetFile, stabilizationDuration: 1.5)

        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isWaitingForFile)
        XCTAssertEqual(manager.mode.targetFileURL, targetFile)
        XCTAssertEqual(systemMock.startCallCount, 1)
        XCTAssertEqual(watcherMock.waitForFileCallCount, 1)
        XCTAssertEqual(watcherMock.lastTargetPath, targetFile)
        XCTAssertEqual(watcherMock.lastStabilizationDuration, 1.5)
        XCTAssertNil(manager.lastError)
    }

    func testTargetFileUpdateUpdatesStabilizingState() {
        let targetFile = tempDir.url.appendingPathComponent("build.iso")
        manager.startWaitingForFile(at: targetFile)

        let stabilizingState = FileWatcherTargetFileState(
            targetPath: targetFile,
            exists: true,
            isStabilizing: true,
            currentSize: 2048
        )
        watcherMock.simulateTargetFileUpdate(stabilizingState)
        XCTAssertTrue(manager.isStabilizingFile)

        let stabilizedState = FileWatcherTargetFileState(
            targetPath: targetFile,
            exists: true,
            isStabilizing: false,
            currentSize: 4096
        )
        watcherMock.simulateTargetFileUpdate(stabilizedState)
        XCTAssertFalse(manager.isStabilizingFile)
    }

    func testTargetFileCompletionAutoStopsSessionAndPostsNotification() async throws {
        let targetFile = tempDir.url.appendingPathComponent("build.iso")
        manager.startWaitingForFile(at: targetFile)

        let notificationExpectation = expectation(
            forNotification: .wakeUpNeoFileDetected,
            object: nil,
            notificationCenter: .default
        )

        watcherMock.simulateTargetFileComplete()

        await fulfillment(of: [notificationExpectation], timeout: 2.0)
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertEqual(systemMock.stopCallCount, 1)
        XCTAssertEqual(watcherMock.stopCallCount, 1)
        XCTAssertFalse(manager.isStabilizingFile)
    }

    // MARK: - Tier 2: Boundary & Error Handling

    func testManualStopCleanlyReleasesWatcherAndAssertions() {
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(manager.isActive)

        manager.stop()

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertEqual(systemMock.stopCallCount, 1)
        XCTAssertEqual(watcherMock.stopCallCount, 1)
        XCTAssertTrue(manager.activeDownloads.isEmpty)

        // Repeated stop is a safe no-op
        manager.stop()
        XCTAssertEqual(systemMock.stopCallCount, 1)
    }

    func testWatcherStartFailureRollsBackAssertionsAndSetsLastError() {
        let dummyError = FileWatcherError.directoryNotFound(tempDir.url)
        watcherMock.shouldThrowOnWatch = dummyError

        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertNotNil(manager.lastError)
        XCTAssertEqual(systemMock.stopCallCount, 1, "Must rollback system sleep assertion if watcher fails")
    }

    func testWatcherRuntimeErrorStopsSessionAndSetsLastError() {
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(manager.isActive)

        let runtimeError = FileWatcherError.unreadablePath(tempDir.url)
        watcherMock.simulateError(runtimeError)

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertNotNil(manager.lastError)
        XCTAssertEqual(systemMock.stopCallCount, 1)
    }

    // MARK: - Tier 3: Mode Transitions & Dynamic Power Settings

    func testModeSwitchFromIndefiniteToWatchingDownloads() {
        manager.startIndefinitely()
        XCTAssertTrue(manager.mode.isIndefinite)

        manager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 1)
    }

    func testModeSwitchFromWatchingDownloadsToTimed() {
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(manager.mode.isWatchingDownloads)

        manager.start(for: 1800)

        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isTimed)
        XCTAssertEqual(watcherMock.stopCallCount, 1, "Must stop watcher on mode switch")
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    func testDynamicPowerSettingsRestartWatcherSession() {
        manager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertEqual(displayMock.startCallCount, 0)

        // Enable display sleep prevention dynamically
        manager.keepDisplayAwake = true

        XCTAssertTrue(manager.mode.isWatchingDownloads)
        XCTAssertEqual(displayMock.startCallCount, 1, "Display assertion should now be active")
        XCTAssertEqual(watcherMock.watchDownloadsCallCount, 2, "Watcher should restart with active session")
    }

    // MARK: - Tier 4: Real DefaultFileWatcherService End-to-End Integration

    func testRealWatcherIntegrationWithSleepManager() async throws {
        let realWatcher = DefaultFileWatcherService()
        let realManager = SleepManager(
            compositeService: composite,
            fileWatcherService: realWatcher
        )

        // Create initial download
        try tempDir.createFile(named: "payload.crdownload", text: "chunk0")

        realManager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(realManager.isActive)
        XCTAssertEqual(realManager.activeDownloads, ["payload.crdownload"])

        let completeExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        // Complete download by renaming to final format
        try tempDir.renameFile(from: "payload.crdownload", to: "payload.zip")

        await fulfillment(of: [completeExpectation], timeout: 4.0)

        XCTAssertFalse(realManager.isActive)
        XCTAssertTrue(realManager.mode.isOff)
        XCTAssertEqual(systemMock.stopCallCount, 1)
    }
}
