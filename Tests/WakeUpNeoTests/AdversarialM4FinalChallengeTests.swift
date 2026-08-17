import XCTest
import Foundation
@testable import WakeUpNeoCore

// MARK: - Safe Threading Box
private final class M4SafeBox<T>: @unchecked Sendable {
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

// MARK: - Adversarial M4 Final Challenge Suite
//
// White-box adversarial coverage hardening and stress verification covering:
// 1. Boundary & Malformed Inputs (Pattern Matcher & Normalization)
// 2. Dynamic Symlinks & Directory/File Transitions in Watcher
// 3. Progressive Directory Package Growth & Mutation for Target Files
// 4. Future Timestamp and Time-Jump Resilience in FileStabilityChecker
// 5. Zero-Byte & Rapid Truncation Oscillations
// 6. High-Contention Concurrency & Race Condition Oracles
// 7. Power Assertion Safety & Anti-Leak Guarantees Under Rapid Mode Thrashing
// 8. Headless Notification Resilience Under High Parallel Contention
// 9. Watcher Startup Failure Error Rollback Guarantees

@MainActor
final class AdversarialM4FinalChallengeTests: XCTestCase {
    
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
        tempDir = try! TestTempDirectory(prefix: "AdversarialM4FinalChallenge")
    }
    
    override func tearDown() {
        sleepManager?.stop()
        watcher?.stop()
        tempDir?.cleanup()
        super.tearDown()
    }
    
    // MARK: - 1. Pattern Matcher: Chaotic & Malformed Inputs Oracle
    
    func testPatternMatcherChaoticInputsOracle() {
        // Extreme character sequences, path separators, control characters, URL encodings
        let validAdversarialNames = [
            "file.crdownload",
            "file.with.many.dots.and.spaces .part",
            "emoji_🚀_download.download",
            "deeply/nested/path/to/archive.tar.gz.!ut",
            "C:\\windows\\style\\path\\file.utpart",
            ".hidden.crdownload",
            "file_with_null_escapes%00.aria2",
            "trailing_newline.tmp\n",
            "\tleading_tab.partial",
            "all_caps_extension.CRDOWNLOAD",
            "mixed_case_extension.pArT",
            "dots...and...dots.download"
        ]
        
        for name in validAdversarialNames {
            XCTAssertTrue(
                DownloadPatternMatcher.isTemporaryDownload(fileName: name),
                "Expected isTemporaryDownload == true for '\(name)'"
            )
        }
        
        let invalidAdversarialNames = [
            "",
            "   ",
            "\n\t",
            "crdownload",
            "part",
            "download",
            "file.crdownload.final",
            "file.part.bak",
            "file.download.zip",
            "file.crdownload.",
            "file.part..",
            ".",
            "..",
            ".DS_Store",
            ".localized"
        ]
        
        for name in invalidAdversarialNames {
            XCTAssertFalse(
                DownloadPatternMatcher.isTemporaryDownload(fileName: name),
                "Expected isTemporaryDownload == false for '\(name)'"
            )
        }
    }
    
    func testPatternMatcherCustomExtensionNormalizationOracle() {
        let messyCustomList: Set<String> = [
            "  .MY_EXT  ",
            "...tripleDot",
            "UPPERCASE",
            "",
            "   ",
            ".",
            "...",
            "🚀rocket",
            "日本語ext"
        ]
        
        let effective = DownloadPatternMatcher.effectiveExtensions(customExtensions: messyCustomList)
        
        // Built-ins must all be present
        for builtin in DownloadPatternMatcher.defaultExtensions {
            XCTAssertTrue(effective.contains(builtin))
        }
        
        // Cleaned custom extensions must be present
        XCTAssertTrue(effective.contains("my_ext"))
        XCTAssertTrue(effective.contains("tripledot"))
        XCTAssertTrue(effective.contains("uppercase"))
        XCTAssertTrue(effective.contains("🚀rocket"))
        XCTAssertTrue(effective.contains("日本語ext"))
        XCTAssertFalse(effective.contains(""))
        
        // Matching test
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "payload.MY_EXT", customExtensions: messyCustomList))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "payload.tripleDot", customExtensions: messyCustomList))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "payload.🚀rocket", customExtensions: messyCustomList))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "payload.日本語ext", customExtensions: messyCustomList))
    }
    
    // MARK: - 2. Symlinks & Directory/File Transitions
    
    func testSymlinkedTargetFileStabilization() async throws {
        // Create real file in a subfolder and symlink to it
        let realDir = try tempDir.createDirectory(named: "real_folder")
        let realFile = realDir.appendingPathComponent("target_real.bin")
        try Data(repeating: 0x42, count: 2048).write(to: realFile)
        
        let symlinkURL = tempDir.url.appendingPathComponent("symlink_target.bin")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realFile)
        
        // When resolving symlink URL
        let resolvedURL = symlinkURL.resolvingSymlinksInPath()
        let checker = FileStabilityChecker(stabilizationDuration: 0.3)
        let state1 = checker.evaluate(at: resolvedURL, now: Date.now)
        XCTAssertTrue(state1.exists)
        XCTAssertEqual(state1.currentSize, 2048)
        
        // Simulate waiting beyond stabilization duration
        let futureDate = Date.now.addingTimeInterval(0.5)
        let state2 = checker.evaluate(at: resolvedURL, now: futureDate)
        XCTAssertTrue(state2.exists)
        XCTAssertFalse(state2.isStabilizing, "Symlinked target file should stabilize when real file is stable")
        XCTAssertEqual(state2.currentSize, 2048)
        
        // Direct symlink metadata also exists
        let directMeta = FileStabilityChecker.readMetadata(at: symlinkURL)
        XCTAssertTrue(directMeta.exists)
        XCTAssertGreaterThan(directMeta.size, 0)
    }
    
    func testSymlinkedDownloadDirectoryMonitoring() async throws {
        // Create real download directory and symlink it
        let realDir = try tempDir.createDirectory(named: "real_downloads")
        let symlinkDir = tempDir.url.appendingPathComponent("symlink_downloads")
        try FileManager.default.createSymbolicLink(at: symlinkDir, withDestinationURL: realDir)
        
        let activeFile = realDir.appendingPathComponent("in_flight.crdownload")
        try Data("in flight data".utf8).write(to: activeFile)
        
        let resolvedDir = symlinkDir.resolvingSymlinksInPath()
        let active = DownloadPatternMatcher.activeDownloads(in: resolvedDir)
        XCTAssertEqual(active, ["in_flight.crdownload"])
        
        // Watch downloads on resolved directory
        let updateCount = M4SafeBox<Int>(0)
        let completeExpectation = expectation(description: "Symlink directory download complete")
        
        try watcher.watchDownloads(
            in: resolvedDir,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { _ in updateCount.set(updateCount.get + 1) },
            onComplete: { completeExpectation.fulfill() },
            onError: { XCTFail("Unexpected error: \($0)") }
        )
        
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(watcher.isWatching)
        
        // Rename file in real directory
        let completedFile = realDir.appendingPathComponent("in_flight.zip")
        try FileManager.default.moveItem(at: activeFile, to: completedFile)
        
        await fulfillment(of: [completeExpectation], timeout: 4.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    // MARK: - 3. Progressive Directory Package Growth for Target Files
    
    func testDirectoryPackageTargetFileProgressiveGrowth() {
        let packageURL = tempDir.url.appendingPathComponent("BundleArtifact.app")
        let checker = FileStabilityChecker(stabilizationDuration: 0.4)
        
        let t0 = Date.now
        
        // 1. Package does not exist yet
        let s0 = checker.evaluate(at: packageURL, now: t0)
        XCTAssertFalse(s0.exists)
        XCTAssertFalse(s0.isStabilizing)
        XCTAssertEqual(s0.currentSize, 0)
        
        // 2. Create directory package structure with file 1
        try? FileManager.default.createDirectory(at: packageURL.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let execURL = packageURL.appendingPathComponent("Contents/MacOS/AppBinary")
        try? Data(repeating: 0x01, count: 5000).write(to: execURL)
        
        let t1 = t0.addingTimeInterval(0.1)
        let s1 = checker.evaluate(at: packageURL, now: t1)
        XCTAssertTrue(s1.exists)
        XCTAssertTrue(s1.isStabilizing)
        XCTAssertEqual(s1.currentSize, 5000)
        
        // 3. Add file 2 to package (Resources/info.dat)
        let resDir = packageURL.appendingPathComponent("Contents/Resources")
        try? FileManager.default.createDirectory(at: resDir, withIntermediateDirectories: true)
        let resURL = resDir.appendingPathComponent("info.dat")
        try? Data(repeating: 0x02, count: 3000).write(to: resURL)
        
        let t2 = t1.addingTimeInterval(0.1)
        let s2 = checker.evaluate(at: packageURL, now: t2)
        XCTAssertTrue(s2.exists)
        XCTAssertTrue(s2.isStabilizing, "Package size increased to 8000 so it must reset stabilization")
        XCTAssertEqual(s2.currentSize, 8000)
        
        // 4. Allow stabilization duration to pass without new writes
        let t3 = t2.addingTimeInterval(0.5)
        let s3 = checker.evaluate(at: packageURL, now: t3)
        XCTAssertTrue(s3.exists)
        XCTAssertFalse(s3.isStabilizing, "Package should be stable now")
        XCTAssertEqual(s3.currentSize, 8000)
    }
    
    // MARK: - 4. Future Timestamp and Time-Jump Resilience
    
    func testFutureModificationDateHandling() {
        let testFileURL = tempDir.url.appendingPathComponent("future_time.dat")
        try? Data("future timestamp content".utf8).write(to: testFileURL)
        
        // Set modification date 1 hour into the future
        let futureDate = Date.now.addingTimeInterval(3600)
        try? FileManager.default.setAttributes([.modificationDate: futureDate], ofItemAtPath: testFileURL.path(percentEncoded: false))
        
        let checker = FileStabilityChecker(stabilizationDuration: 0.3)
        let t0 = Date.now
        
        // First observation: timeSinceLastModification is negative!
        let s0 = checker.evaluate(at: testFileURL, now: t0)
        XCTAssertTrue(s0.exists)
        XCTAssertTrue(s0.isStabilizing, "Future dated file must NOT trigger fast path and should stabilize normally")
        
        // Second observation after stabilizationDuration
        let t1 = t0.addingTimeInterval(0.4)
        let s1 = checker.evaluate(at: testFileURL, now: t1)
        XCTAssertTrue(s1.exists)
        XCTAssertFalse(s1.isStabilizing, "Future dated file should stabilize once observed quiet period elapses")
    }
    
    // MARK: - 5. Zero-Byte & Rapid Truncation Oscillations
    
    func testZeroByteTargetFileStabilizationAndReGrowth() {
        let targetURL = tempDir.url.appendingPathComponent("oscillating_file.dat")
        let checker = FileStabilityChecker(stabilizationDuration: 0.3)
        
        // Create 0-byte file
        try? Data().write(to: targetURL)
        let t0 = Date.now
        
        let s0 = checker.evaluate(at: targetURL, now: t0)
        XCTAssertTrue(s0.exists)
        XCTAssertEqual(s0.currentSize, 0)
        
        // Settle at 0 bytes
        let t1 = t0.addingTimeInterval(0.4)
        let s1 = checker.evaluate(at: targetURL, now: t1)
        XCTAssertTrue(s1.exists)
        XCTAssertFalse(s1.isStabilizing, "0-byte file must stabilize after quiet window")
        
        // Now file unexpectedly begins receiving bytes (resumes download or logging)
        try? Data("appended bytes".utf8).write(to: targetURL)
        let t2 = t1.addingTimeInterval(0.1)
        let s2 = checker.evaluate(at: targetURL, now: t2)
        XCTAssertTrue(s2.exists)
        XCTAssertTrue(s2.isStabilizing, "Stabilization must be broken when file size changes from 0 to positive")
        XCTAssertEqual(s2.currentSize, 14)
        
        // Truncate back to 0 bytes
        try? Data().write(to: targetURL)
        let t3 = t2.addingTimeInterval(0.1)
        let s3 = checker.evaluate(at: targetURL, now: t3)
        XCTAssertTrue(s3.exists)
        XCTAssertTrue(s3.isStabilizing, "Stabilization must be broken when truncated back to 0")
        XCTAssertEqual(s3.currentSize, 0)
        
        // Settle again
        let t4 = t3.addingTimeInterval(0.4)
        let s4 = checker.evaluate(at: targetURL, now: t4)
        XCTAssertTrue(s4.exists)
        XCTAssertFalse(s4.isStabilizing, "Should stabilize again after second quiet period")
    }
    
    // MARK: - 6. High-Contention Concurrency & Race Condition Oracles
    
    func testHighContentionPatternMatcherConcurrency() async {
        let iterations = 1000
        let inputs = [
            "archive.tar.gz.part",
            "not_a_download.pdf",
            "file.crdownload",
            "safari.download",
            "random.tmp",
            "normal.docx",
            "video.mp4.partial"
        ]
        
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    for _ in 0..<iterations {
                        let name = inputs.randomElement()!
                        let isTemp = DownloadPatternMatcher.isTemporaryDownload(fileName: name)
                        let normalized = DownloadPatternMatcher.normalizeExtension(name)
                        XCTAssertFalse(normalized.hasPrefix("."))
                        if name.contains(".part") || name.contains(".crdownload") || name.contains(".download") || name.contains(".tmp") || name.contains(".partial") {
                            XCTAssertTrue(isTemp)
                        } else {
                            XCTAssertFalse(isTemp)
                        }
                    }
                }
            }
        }
    }
    
    func testHighContentionFileStabilityCheckerConcurrency() async throws {
        let targetURL = tempDir.url.appendingPathComponent("concurrent_checker_test.bin")
        try Data("initial data".utf8).write(to: targetURL)
        let checker = FileStabilityChecker(stabilizationDuration: 0.5)
        
        await withTaskGroup(of: Void.self) { group in
            // 8 reader/evaluator tasks
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<50 {
                        let state = checker.evaluate(at: targetURL)
                        XCTAssertTrue(state.exists)
                        try? await Task.sleep(for: .milliseconds(5))
                    }
                }
            }
            
            // 2 writer tasks modifying the file
            for w in 0..<2 {
                group.addTask {
                    for i in 0..<20 {
                        let data = Data("Writer \(w) chunk \(i)\n".utf8)
                        try? data.write(to: targetURL)
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                }
            }
        }
    }
    
    // MARK: - 7. Power Assertion Safety & Anti-Leak Under Rapid Mode Thrashing
    
    func testRapidModeSwitchingAssertionSafetyAndNoLeak() async throws {
        let downloadDir = try tempDir.createDirectory(named: "thrash_downloads")
        let targetFile = tempDir.url.appendingPathComponent("thrash_target.bin")
        
        for iteration in 1...25 {
            switch iteration % 5 {
            case 0:
                sleepManager.startIndefinitely()
                XCTAssertEqual(sleepManager.mode, .indefinite)
                XCTAssertTrue(systemMock.isRunning)
            case 1:
                sleepManager.start(for: 300)
                XCTAssertTrue(sleepManager.mode.isTimed)
                XCTAssertTrue(systemMock.isRunning)
            case 2:
                sleepManager.startWatchingDownloads(directory: downloadDir)
                XCTAssertTrue(sleepManager.mode.isWatchingDownloads)
                XCTAssertTrue(systemMock.isRunning)
            case 3:
                sleepManager.startWaitingForFile(at: targetFile, stabilizationDuration: 0.5)
                XCTAssertTrue(sleepManager.mode.isWaitingForFile)
                XCTAssertTrue(systemMock.isRunning)
            case 4:
                sleepManager.stop()
                XCTAssertEqual(sleepManager.mode, .off)
                XCTAssertFalse(systemMock.isRunning)
            default:
                break
            }
            
            if iteration % 3 == 0 {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        
        // Final stop
        sleepManager.stop()
        
        // Assert clean teardown and zero power assertion leaks
        XCTAssertEqual(sleepManager.mode, .off)
        XCTAssertFalse(sleepManager.isActive)
        XCTAssertFalse(systemMock.isRunning, "System power assertion must be completely released")
        XCTAssertFalse(displayMock.isRunning, "Display power assertion must be completely released")
        XCTAssertFalse(watcher.isWatching, "File watcher service must be completely stopped")
        XCTAssertNil(sleepManager.lastError)
    }
    
    // MARK: - 8. Headless Notification Resilience
    
    func testNotificationServiceHeadlessParallelInvocations() async {
        let service = NotificationService()
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    await service.requestAuthorization()
                    service.sendSessionEndedNotification()
                    service.sendSessionExpiringSoonNotification(minutesRemaining: i)
                    service.sendDownloadsCompletedNotification(directory: URL(fileURLWithPath: "/Downloads"))
                    service.sendFileDetectedNotification(targetURL: URL(fileURLWithPath: "/Downloads/file.pkg"))
                }
            }
        }
    }
    
    // MARK: - 9. Error Rollback on Nonexistent Directory When Starting Watcher
    
    func testWatcherStartupFailureRollsBackPowerAssertionsCleanly() {
        let nonExistentDir = URL(fileURLWithPath: "/path/to/nonexistent/directory/\(UUID().uuidString)")
        
        // Start watching nonexistent directory
        sleepManager.startWatchingDownloads(directory: nonExistentDir)
        
        // Verify assertions were rolled back and error captured
        XCTAssertFalse(sleepManager.isActive, "Session must be inactive after startup failure")
        XCTAssertEqual(sleepManager.mode, .off)
        XCTAssertFalse(systemMock.isRunning, "System sleep assertion must NOT leak on failure")
        XCTAssertFalse(displayMock.isRunning, "Display sleep assertion must NOT leak on failure")
        XCTAssertNotNil(sleepManager.lastError, "Startup error must be recorded in lastError")
        
        // Clear error
        sleepManager.clearError()
        XCTAssertNil(sleepManager.lastError)
    }
    
    func testTargetFileWatcherStartupFailureOnNonexistentParentDirectory() {
        let nonExistentParent = URL(fileURLWithPath: "/nonexistent_parent_dir_\(UUID().uuidString)/target.dmg")
        
        sleepManager.startWaitingForFile(at: nonExistentParent, stabilizationDuration: 1.0)
        
        XCTAssertFalse(sleepManager.isActive)
        XCTAssertEqual(sleepManager.mode, .off)
        XCTAssertFalse(systemMock.isRunning)
        XCTAssertFalse(displayMock.isRunning)
        XCTAssertNotNil(sleepManager.lastError)
        
        sleepManager.clearError()
        XCTAssertNil(sleepManager.lastError)
    }
}
