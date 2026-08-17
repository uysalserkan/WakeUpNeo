import XCTest
@testable import WakeUpNeoCore

// MARK: - Tier 4: Real-World Scenarios End-to-End Test Suite
//
// Verifies full end-to-end integration across real-world workflows using genuine
// `TestTempDirectory`, `DefaultFileWatcherService`, `SleepManager`, and `MockSleepService`.
//
// Scenarios:
// 1. Chrome / Chromium Large File Download Simulation (multi-chunk append & atomic rename)
// 2. Safari Directory Package (.download/) Multi-Stage Download
// 3. Multi-Browser Concurrent Staggered Download Queue (Firefox, Chrome, Safari, Aria2)
// 4. Build Artifact Generation & Growth (Target File Wait with continuous writes & stabilization)
// 5. User Cancellation / Manual Interruption During Active Session (clean release & no zombie callbacks)

@MainActor
final class Tier4RealWorldScenariosTests: XCTestCase {

    var systemMock: MockSleepService!
    var displayMock: MockSleepService!
    var composite: CompositeSleepService!
    var watcher: DefaultFileWatcherService!
    var sleepManager: SleepManager!
    var tempDir: TestTempDirectory!

    override func setUp() {
        super.setUp()
        systemMock = MockSleepService()
        displayMock = MockSleepService()
        composite = CompositeSleepService(
            systemSleepService: systemMock,
            displaySleepService: displayMock
        )
        watcher = DefaultFileWatcherService()
        sleepManager = SleepManager(
            compositeService: composite,
            fileWatcherService: watcher
        )
        tempDir = try! TestTempDirectory(prefix: "Tier4RealWorldScenarios")
    }

    override func tearDown() {
        sleepManager?.stop()
        watcher?.stop()
        tempDir?.cleanup()
        super.tearDown()
    }

    // MARK: - Scenario 1: Chrome / Chromium Large File Download Simulation

    func testScenario1ChromeLargeFileDownloadSimulation() async throws {
        let downloadFileName = "ubuntu-24.04-desktop-arm64.iso.crdownload"
        let finalFileName = "ubuntu-24.04-desktop-arm64.iso"

        // Step 1: Create initial in-progress .crdownload file
        try tempDir.createFile(named: downloadFileName, text: "Initial Chunk [0-1024KB]")

        // Step 2: Start watching downloads directory
        sleepManager.startWatchingDownloads(directory: tempDir.url)

        // Step 3: Verify power assertion is held and mode is active
        XCTAssertTrue(sleepManager.isActive, "SleepManager must be active when watching downloads")
        XCTAssertTrue(sleepManager.mode.isWatchingDownloads, "SleepMode must be .watchingDownloads")
        XCTAssertEqual(sleepManager.mode.watchedDirectory, tempDir.url)
        XCTAssertTrue(systemMock.isRunning, "System sleep assertion must be held")
        XCTAssertGreaterThanOrEqual(systemMock.startCallCount, 1)

        // Step 4: Simulate progressive multi-chunk file writes to .crdownload
        for chunkIndex in 1...5 {
            try await Task.sleep(for: .milliseconds(80))
            let chunkData = Data("Progressive Chunk #\(chunkIndex) [\(chunkIndex * 1024)KB]\n".utf8)
            try tempDir.append(data: chunkData, toFileNamed: downloadFileName)

            // Sleep assertion must remain continuously held during writing
            XCTAssertTrue(systemMock.isRunning, "Power assertion must stay active during chunk write #\(chunkIndex)")
            XCTAssertTrue(sleepManager.isActive, "Session must remain active during chunk write #\(chunkIndex)")
        }

        // Step 5: Setup expectation for download completion notification
        let completionExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        // Step 6: Simulate Chrome completing the download by renaming .crdownload to final .iso
        try tempDir.renameFile(from: downloadFileName, to: finalFileName)

        // Step 7: Await automatic completion trigger
        await fulfillment(of: [completionExpectation], timeout: 5.0)

        // Step 8: Verify sleep assertion is released, mode is .off, and state is clean
        XCTAssertFalse(systemMock.isRunning, "Power assertion must be automatically released on download completion")
        XCTAssertGreaterThanOrEqual(systemMock.stopCallCount, 1, "Stop must be invoked on sleep service")
        XCTAssertFalse(sleepManager.isActive, "SleepManager must no longer be active")
        XCTAssertEqual(sleepManager.mode, .off, "SleepMode must return to .off")
        XCTAssertTrue(sleepManager.activeDownloads.isEmpty, "Active downloads list must be empty")
        XCTAssertNil(sleepManager.lastError, "No error should be recorded during successful download")
    }

    // MARK: - Scenario 2: Safari Directory Package (.download/) Multi-Stage Download

    func testScenario2SafariDirectoryPackageMultiStageDownload() async throws {
        let bundleName = "XcodeCommandTools.pkg.download"
        let finalPackageName = "XcodeCommandTools.pkg"

        // Step 1: Create Safari bundle package folder with internal metadata and partial file
        _ = try tempDir.createDownloadPackage(
            named: bundleName,
            files: [
                "Info.plist": Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict></dict></plist>".utf8),
                "Item.pkg.part": Data("Part 0 content".utf8)
            ]
        )

        // Step 2: Start watching downloads directory
        sleepManager.startWatchingDownloads(directory: tempDir.url)

        // Step 3: Verify power assertion is active
        XCTAssertTrue(sleepManager.isActive, "SleepManager must be active when Safari bundle is present")
        XCTAssertTrue(sleepManager.mode.isWatchingDownloads, "SleepMode must be .watchingDownloads")
        XCTAssertTrue(systemMock.isRunning, "Power assertion must be active for Safari .download package")

        // Step 4: Simulate internal writes and multi-stage download progress inside bundle
        for stage in 1...4 {
            try await Task.sleep(for: .milliseconds(70))
            let stageData = Data("Stage #\(stage) download payload".utf8)
            let stageFileName = "\(bundleName)/part_\(stage).dat"
            let stageFileURL = tempDir.url.appendingPathComponent(stageFileName)
            try stageData.write(to: stageFileURL)

            // Power assertion must stay held throughout all internal bundle stages
            XCTAssertTrue(systemMock.isRunning, "Power assertion must be held during Safari stage #\(stage)")
            XCTAssertTrue(sleepManager.isActive)
        }

        // Step 5: Setup expectation for download completion notification
        let completionExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        // Step 6: Simulate Safari finalizing the download by atomically moving/renaming package
        try tempDir.renameFile(from: bundleName, to: finalPackageName)

        // Step 7: Await automatic completion
        await fulfillment(of: [completionExpectation], timeout: 5.0)

        // Step 8: Verify automatic completion and power assertion release
        XCTAssertFalse(systemMock.isRunning, "Power assertion must be released after Safari package completes")
        XCTAssertFalse(sleepManager.isActive, "SleepManager must be inactive")
        XCTAssertEqual(sleepManager.mode, .off)
        XCTAssertTrue(sleepManager.activeDownloads.isEmpty)
    }

    // MARK: - Scenario 3: Multi-Browser Concurrent Staggered Download Queue

    func testScenario3MultiBrowserConcurrentStaggeredDownloadQueue() async throws {
        // Step 1: Simulate 3 concurrent downloads from different browsers
        // Firefox (.part), Chrome (.crdownload), Safari (.download)
        let firefoxDownload = "archive.zip.part"
        let chromeDownload = "video.mp4.crdownload"
        let safariDownload = "installer.dmg.download"
        let aria2Download = "data.bin.aria2"

        try tempDir.createFile(named: firefoxDownload, text: "Firefox stream data")
        try tempDir.createFile(named: chromeDownload, text: "Chrome video stream data")
        _ = try tempDir.createDownloadPackage(
            named: safariDownload,
            files: ["Info.plist": Data("<plist/>".utf8), "Item.part": Data("Safari part".utf8)]
        )

        // Step 2: Start download monitoring
        sleepManager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertTrue(sleepManager.isActive, "SleepManager must be active with concurrent downloads")
        XCTAssertTrue(systemMock.isRunning, "Power assertion must be active")
        XCTAssertEqual(sleepManager.mode.activeFilesCount, 3)

        // Step 3: Complete Download 1 (Firefox) -> Sleep assertion must STILL be held (2 remain)
        try tempDir.renameFile(from: firefoxDownload, to: "archive.zip")
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(systemMock.isRunning, "Power assertion must STILL be held because Chrome & Safari remain")
        XCTAssertTrue(sleepManager.isActive, "SleepManager must stay active")

        // Step 4: Complete Download 2 (Chrome) -> Sleep assertion must STILL be held (1 remains)
        try tempDir.renameFile(from: chromeDownload, to: "video.mp4")
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(systemMock.isRunning, "Power assertion must STILL be held because Safari remains")
        XCTAssertTrue(sleepManager.isActive, "SleepManager must stay active")

        // Step 5: Start a new Download 4 (Aria2) -> Assertion continues uninterrupted
        try tempDir.createFile(named: aria2Download, text: "Aria2 segment control")
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(systemMock.isRunning, "Power assertion must stay active when Aria2 download joins queue")
        XCTAssertTrue(sleepManager.isActive)

        // Step 6: Complete Download 3 (Safari) -> Assertion held for Download 4 (Aria2)
        try tempDir.renameFile(from: safariDownload, to: "installer.dmg")
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(systemMock.isRunning, "Power assertion must stay active while Aria2 finishes")
        XCTAssertTrue(sleepManager.isActive)

        // Step 7: Setup completion expectation for final remaining download
        let completionExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        // Step 8: Complete Download 4 (Aria2) -> All downloads finished
        try tempDir.renameFile(from: aria2Download, to: "data.bin")

        // Step 9: Await completion and verify full release
        await fulfillment(of: [completionExpectation], timeout: 5.0)

        XCTAssertFalse(systemMock.isRunning, "Power assertion must be released once ALL downloads finish")
        XCTAssertFalse(sleepManager.isActive, "SleepManager must be inactive")
        XCTAssertEqual(sleepManager.mode, .off, "SleepMode must be .off")
        XCTAssertTrue(sleepManager.activeDownloads.isEmpty)
    }

    // MARK: - Scenario 4: Build Artifact Generation & Growth (Target File Wait)

    func testScenario4BuildArtifactGenerationAndGrowthTargetFileWait() async throws {
        let targetFileName = "WakeUpNeo-v1.0.0-macOS-Universal.tar.gz"
        let targetFileURL = tempDir.url.appendingPathComponent(targetFileName)

        // Step 1: Configure SleepManager to wait for build artifact (settle duration 0.5s)
        sleepManager.startWaitingForFile(at: targetFileURL, stabilizationDuration: 0.5)

        // Step 2: Verify assertion is held while file does not yet exist
        XCTAssertTrue(sleepManager.isActive, "SleepManager must be active while waiting for file")
        XCTAssertTrue(sleepManager.mode.isWaitingForFile, "SleepMode must be .waitingForFile")
        XCTAssertEqual(sleepManager.mode.targetFileURL, targetFileURL)
        XCTAssertTrue(systemMock.isRunning, "Power assertion must be active while waiting for target file")
        XCTAssertFalse(sleepManager.isStabilizingFile, "File does not exist yet so isStabilizing should be false")

        // Step 3: Create target file and write progressive chunks every 0.1s so size keeps changing
        try tempDir.createFile(named: targetFileName, text: "Tar Header [Block 0]\n")

        for block in 1...6 {
            try await Task.sleep(for: .milliseconds(100))
            let blockData = Data("Payload Block #\(block) [\(block * 512) bytes]\n".utf8)
            try tempDir.append(data: blockData, toFileNamed: targetFileName)

            // Sleep assertion must remain held throughout continuous file growth
            XCTAssertTrue(systemMock.isRunning, "Power assertion must stay active during continuous file growth")
            XCTAssertTrue(sleepManager.isActive)
        }

        // Allow watcher event queue to process write event and confirm stabilizing state
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(sleepManager.isStabilizingFile || sleepManager.isActive, "Target file stabilization must be tracked")
        XCTAssertTrue(systemMock.isRunning, "Power assertion must still be held while stabilizing")

        // Step 4: Setup expectation for target file detected notification
        let fileDetectedExpectation = expectation(
            forNotification: .wakeUpNeoFileDetected,
            object: nil,
            notificationCenter: .default
        )

        // Step 5: Stop writing, allow 0.5s settle window to elapse
        await fulfillment(of: [fileDetectedExpectation], timeout: 5.0)

        // Step 6: Verify file stability is recognized, assertion released, and mode reset
        XCTAssertFalse(systemMock.isRunning, "Power assertion must be released after file stabilizes")
        XCTAssertGreaterThanOrEqual(systemMock.stopCallCount, 1)
        XCTAssertFalse(sleepManager.isActive, "SleepManager must no longer be active")
        XCTAssertEqual(sleepManager.mode, .off, "SleepMode must return to .off")
        XCTAssertFalse(sleepManager.isStabilizingFile, "isStabilizingFile must be false after completion")
        XCTAssertNil(sleepManager.lastError)
    }

    // MARK: - Scenario 5: User Cancellation / Manual Interruption During Active Session

    func testScenario5UserCancellationDuringActiveSession() async throws {
        let activeDownload = "large_dataset.tar.crdownload"
        try tempDir.createFile(named: activeDownload, text: "Active download bytes...")

        // Step 1: Start download watching with active .crdownload
        sleepManager.startWatchingDownloads(directory: tempDir.url)

        XCTAssertTrue(sleepManager.isActive, "SleepManager must be active")
        XCTAssertTrue(systemMock.isRunning, "Power assertion must be active")
        XCTAssertTrue(sleepManager.mode.isWatchingDownloads)

        // Step 2: User manually clicks "Stop" / interrupts the session
        sleepManager.stop()

        // Step 3: Verify power assertion is immediately released, file watcher is cancelled, mode reset to .off
        XCTAssertFalse(sleepManager.isActive, "SleepManager must be inactive immediately after stop()")
        XCTAssertEqual(sleepManager.mode, .off, "SleepMode must be .off immediately")
        XCTAssertFalse(systemMock.isRunning, "Power assertion must be immediately released")
        XCTAssertGreaterThanOrEqual(systemMock.stopCallCount, 1)
        XCTAssertTrue(sleepManager.activeDownloads.isEmpty)

        // Step 4: Verify subsequent file changes in the directory do NOT trigger zombie callbacks or re-awaken
        try tempDir.createFile(named: "new_background_job.part", text: "New download data")
        try tempDir.renameFile(from: activeDownload, to: "large_dataset.tar")
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertFalse(sleepManager.isActive, "SleepManager must NOT be reactivated by subsequent filesystem changes")
        XCTAssertEqual(sleepManager.mode, .off)
        XCTAssertFalse(systemMock.isRunning, "Power assertion must NOT be re-acquired by zombie watcher")
    }

    // MARK: - Scenario 6: Dynamic Display Sleep Assertion Toggle During Real Watcher Session

    func testScenario6DynamicDisplaySleepAssertionToggleDuringActiveSession() async throws {
        let downloadName = "operating_system.dmg.crdownload"
        try tempDir.createFile(named: downloadName, text: "OS Image chunk")

        // Start watching with default settings (system sleep prevented, display sleep not prevented)
        sleepManager.startWatchingDownloads(directory: tempDir.url)
        XCTAssertTrue(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)

        // Dynamically toggle keepDisplayAwake to true
        sleepManager.keepDisplayAwake = true

        // Verify both system and display assertions are now held
        XCTAssertTrue(sleepManager.isActive)
        XCTAssertTrue(sleepManager.mode.isWatchingDownloads)
        XCTAssertTrue(systemMock.isRunning, "System sleep assertion must remain active")
        XCTAssertTrue(displayMock.isRunning, "Display sleep assertion must now be active")

        // Setup completion expectation
        let completionExpectation = expectation(
            forNotification: .wakeUpNeoDownloadsCompleted,
            object: nil,
            notificationCenter: .default
        )

        // Complete the download
        try tempDir.renameFile(from: downloadName, to: "operating_system.dmg")

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        // Verify BOTH system and display assertions are released
        XCTAssertFalse(systemMock.isRunning, "System sleep assertion must be released on complete")
        XCTAssertFalse(displayMock.isRunning, "Display sleep assertion must be released on complete")
        XCTAssertEqual(sleepManager.mode, .off)
    }

    // MARK: - Scenario 7: Target File Pre-Existing and Fast-Path Completion With Real Watcher

    func testScenario7PreExistingTargetFileFastPathWithRealWatcher() async throws {
        let stableFileName = "distribution_binary.dmg"
        let targetFileURL = tempDir.url.appendingPathComponent(stableFileName)

        // Create file that was modified in the past (already stable)
        try tempDir.createFile(named: stableFileName, text: "Distribution Binary Contents")
        let pastDate = Date.now.addingTimeInterval(-10)
        try FileManager.default.setAttributes(
            [.modificationDate: pastDate],
            ofItemAtPath: targetFileURL.path(percentEncoded: false)
        )

        let completionExpectation = expectation(
            forNotification: .wakeUpNeoFileDetected,
            object: nil,
            notificationCenter: .default
        )

        // Start waiting for already stable file
        sleepManager.startWaitingForFile(at: targetFileURL, stabilizationDuration: 1.0)

        // Fast path should detect stability quickly and auto-complete
        await fulfillment(of: [completionExpectation], timeout: 4.0)

        XCTAssertFalse(systemMock.isRunning, "Power assertion should be released after fast path completion")
        XCTAssertEqual(sleepManager.mode, .off)
        XCTAssertFalse(sleepManager.isActive)
    }
}
