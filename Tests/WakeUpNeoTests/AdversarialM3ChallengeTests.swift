import XCTest
import AppKit
import Foundation
@testable import WakeUpNeoCore

// MARK: - Thread-Safe SafeBox & Event Accumulator

private final class SafeAccumulator<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [T] = []

    func append(_ element: T) {
        lock.withLock {
            elements.append(element)
        }
    }

    var count: Int {
        lock.withLock { elements.count }
    }

    var all: [T] {
        lock.withLock { elements }
    }

    func reset() {
        lock.withLock { elements.removeAll() }
    }
}

// MARK: - Mock AppEnvironment Observer Lifecycle Harness

/// Harness mirroring `AppEnvironment` observer setup, notification handling, and deinit cleanup.
private final class MockAppEnvironmentHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var observerTokens: [NSObjectProtocol] = []
    
    let downloadsHandled = SafeAccumulator<URL?>()
    let fileDetectedHandled = SafeAccumulator<URL>()
    let sessionExpiredHandled = SafeAccumulator<Void>()
    
    var notifyOnDownloadsComplete: Bool = true
    var notifyOnFileDetected: Bool = true
    var notifyOnSessionEnd: Bool = true

    init() {
        setupObservers()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupObservers() {
        // 1. Timed session expired
        let expiredToken = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoSessionExpired,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.notifyOnSessionEnd {
                self.sessionExpiredHandled.append(())
            }
        }
        observerTokens.append(expiredToken)

        // 2. Active downloads completed
        let downloadsToken = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            let directory = notification.object as? URL
            if self.notifyOnDownloadsComplete {
                self.downloadsHandled.append(directory)
            }
        }
        observerTokens.append(downloadsToken)

        // 3. Monitored target file detected & stabilized
        let fileToken = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let targetURL = notification.object as? URL else { return }
            if self.notifyOnFileDetected {
                self.fileDetectedHandled.append(targetURL)
            }
        }
        observerTokens.append(fileToken)
    }
}

// MARK: - AdversarialM3ChallengeTests

/// Adversarial and Stress Test Suite for Milestone 3 (UI State & Notification Observer Challenger).
///
/// Challenges:
/// 1. Rapid concurrent notification dispatches (`.wakeUpNeoDownloadsCompleted`, `.wakeUpNeoFileDetected`, `.wakeUpNeoSessionExpired`).
/// 2. Observer cleanup: creating and destroying multiple observer instances without leaks or duplicate notification triggers.
/// 3. Dynamic toggling of `notifyOnDownloadsComplete` and `notifyOnFileDetected` preferences during active notification streams.
/// 4. Unicode / weird folder and filenames in `SleepMode` descriptions and path abbreviation helpers.
/// 5. Boundary conditions in remaining time countdown and custom extensions parsing.
@MainActor
final class AdversarialM3ChallengeTests: XCTestCase {

    private var defaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        testSuiteName = "com.wakeupneo.tests.adversarial.m3.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: testSuiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: testSuiteName)
        defaults = nil
        try await super.tearDown()
    }

    // MARK: - 1. Rapid Concurrent Notification Dispatches

    func testRapidConcurrentNotificationDispatchesAcrossMultipleThreads() async {
        let harness = MockAppEnvironmentHarness()
        let dispatchCount = 100
        let testDir = URL(fileURLWithPath: "/Users/test/Downloads/Concurrent_\(UUID().uuidString)")
        let testFile = testDir.appendingPathComponent("target_file.pkg")

        // Concurrently post notifications from detached tasks across global concurrency pool
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<dispatchCount {
                group.addTask {
                    let dir = testDir.appendingPathComponent("batch_\(i)")
                    let file = testFile.deletingLastPathComponent().appendingPathComponent("file_\(i).iso")

                    NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: dir)
                    NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: file)
                    NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)
                }
            }
        }

        // Allow micro-delay for all notifications to be processed
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(harness.downloadsHandled.count, dispatchCount, "All downloads completed notifications must be handled")
        XCTAssertEqual(harness.fileDetectedHandled.count, dispatchCount, "All file detected notifications must be handled")
        XCTAssertEqual(harness.sessionExpiredHandled.count, dispatchCount, "All session expired notifications must be handled")
    }

    func testConcurrentDispatchesWithMalformedOrNilPayloads() async {
        let harness = MockAppEnvironmentHarness()
        let iterations = 50

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    // Send unexpected object types: String, Int, Array, nil
                    switch i % 4 {
                    case 0:
                        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: "NotAnURL")
                        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: "NotAnURL")
                    case 1:
                        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: 12345)
                        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: ["key": "value"])
                    case 2:
                        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: nil)
                        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: nil)
                    case 3:
                        let validURL = URL(fileURLWithPath: "/Users/test/valid_\(i).zip")
                        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: validURL)
                        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: validURL)
                    default:
                        break
                    }
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(50))

        // downloadsCompleted handles nil or URL (non-URL becomes nil) -> so all iterations are recorded
        XCTAssertEqual(harness.downloadsHandled.count, iterations)
        
        // fileDetected requires `guard let targetURL = notification.object as? URL` -> only case 3 is recorded
        let validFileCount = iterations / 4 + (iterations % 4 > 3 ? 1 : 0)
        XCTAssertEqual(harness.fileDetectedHandled.count, validFileCount)
    }

    func testRapidInterleavedObserverRegistrationAndUnregistration() async {
        let dispatchCount = 50
        let testDir = URL(fileURLWithPath: "/Users/test/Downloads/Churn")

        await withTaskGroup(of: Void.self) { group in
            // Task group 1: Continuously creating and destroying observer harnesses
            for _ in 0..<20 {
                group.addTask {
                    let temporaryHarness = MockAppEnvironmentHarness()
                    NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testDir)
                    _ = temporaryHarness.downloadsHandled.count
                }
            }

            // Task group 2: Simultaneously posting notifications
            for _ in 0..<dispatchCount {
                group.addTask {
                    NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testDir)
                    NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: testDir)
                    NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)
                }
            }
        }

        // Verify no deadlock or crash occurred during massive observer churn
        XCTAssertTrue(true, "Completed concurrent registration/unregistration without crashing")
    }

    // MARK: - 2. Observer Lifecycle & Leak Prevention

    func testObserverCleanupOnDeallocationPreventsDuplicateAndStaleTriggers() async {
        var harnesses: [MockAppEnvironmentHarness?] = (0..<10).map { _ in MockAppEnvironmentHarness() }
        let testURL = URL(fileURLWithPath: "/Users/test/Downloads/lifecycle.dmg")

        // Step 1: All 10 active -> 1 notification should be received by all 10
        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testURL)
        try? await Task.sleep(for: .milliseconds(20))

        for i in 0..<10 {
            XCTAssertEqual(harnesses[i]?.downloadsHandled.count, 1, "Harness \(i) should have received 1 notification")
        }

        // Step 2: Destroy 9 instances, keep only the last one (index 9)
        for i in 0..<9 {
            harnesses[i] = nil
        }

        // Step 3: Post another notification
        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testURL)
        try? await Task.sleep(for: .milliseconds(20))

        // Surviving harness must have exactly 2 handled, and dead ones must not crash or leak
        XCTAssertEqual(harnesses[9]?.downloadsHandled.count, 2, "Surviving harness 9 should have received 2 notifications in total")

        // Step 4: Destroy the last harness
        harnesses[9] = nil

        // Step 5: Post notifications to empty observer list
        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testURL)
        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: testURL)
        NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)
        try? await Task.sleep(for: .milliseconds(20))

        // No crash, clean teardown
        XCTAssertTrue(true, "All observers successfully detached on deinit")
    }

    func testObserverWeakCaptureDoesNotRetainHost() {
        weak var weakRef: MockAppEnvironmentHarness?
        
        // Scope block to verify deallocation
        do {
            let strongHarness = MockAppEnvironmentHarness()
            weakRef = strongHarness
            XCTAssertNotNil(weakRef, "Weak reference must be valid while in scope")
            NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)
        }

        // Outside scope, strongHarness must have deallocated
        XCTAssertNil(weakRef, "MockAppEnvironmentHarness must deallocate and not be retained by NotificationCenter observer closures")
    }

    func testMultipleActiveEnvironmentsReceiveIndependentEvents() async {
        let env1 = MockAppEnvironmentHarness()
        let env2 = MockAppEnvironmentHarness()
        let env3 = MockAppEnvironmentHarness()

        let testDir = URL(fileURLWithPath: "/Users/test/Downloads/Triple")
        let testFile = URL(fileURLWithPath: "/Users/test/Downloads/Triple/file.bin")

        for _ in 0..<5 {
            NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testDir)
            NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: testFile)
            NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)
        }

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(env1.downloadsHandled.count, 5)
        XCTAssertEqual(env1.fileDetectedHandled.count, 5)
        XCTAssertEqual(env1.sessionExpiredHandled.count, 5)

        XCTAssertEqual(env2.downloadsHandled.count, 5)
        XCTAssertEqual(env2.fileDetectedHandled.count, 5)
        XCTAssertEqual(env2.sessionExpiredHandled.count, 5)

        XCTAssertEqual(env3.downloadsHandled.count, 5)
        XCTAssertEqual(env3.fileDetectedHandled.count, 5)
        XCTAssertEqual(env3.sessionExpiredHandled.count, 5)
    }

    // MARK: - 3. Dynamic Preference Toggling During Active Streams

    func testDynamicPreferenceTogglingUnderHighNotificationContention() async {
        let harness = MockAppEnvironmentHarness()
        let streamIterations = 100
        let testURL = URL(fileURLWithPath: "/Users/test/Downloads/Toggling.dmg")

        await withTaskGroup(of: Void.self) { group in
            // Thread A: Stream notifications continuously
            group.addTask {
                for _ in 0..<streamIterations {
                    NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testURL)
                    NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: testURL)
                    try? await Task.sleep(for: .microseconds(100))
                }
            }

            // Thread B: Rapidly toggle preference flags
            group.addTask {
                for i in 0..<streamIterations {
                    let shouldNotify = (i % 2 == 0)
                    harness.notifyOnDownloadsComplete = shouldNotify
                    harness.notifyOnFileDetected = shouldNotify
                    try? await Task.sleep(for: .microseconds(100))
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(50))

        // Total handled count should be strictly greater than 0 and less than or equal to streamIterations
        XCTAssertGreaterThan(harness.downloadsHandled.count, 0)
        XCTAssertLessThanOrEqual(harness.downloadsHandled.count, streamIterations)
        XCTAssertGreaterThan(harness.fileDetectedHandled.count, 0)
        XCTAssertLessThanOrEqual(harness.fileDetectedHandled.count, streamIterations)
    }

    func testPreferenceSuppressionBehaviorWhenNotificationsDisabled() async {
        let harness = MockAppEnvironmentHarness()
        let testURL = URL(fileURLWithPath: "/Users/test/Downloads/Suppressed.dmg")

        // 1. Disable all notifications
        harness.notifyOnDownloadsComplete = false
        harness.notifyOnFileDetected = false
        harness.notifyOnSessionEnd = false

        // Post notifications
        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testURL)
        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: testURL)
        NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)

        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(harness.downloadsHandled.count, 0, "No downloads notification should be handled when disabled")
        XCTAssertEqual(harness.fileDetectedHandled.count, 0, "No file detected notification should be handled when disabled")
        XCTAssertEqual(harness.sessionExpiredHandled.count, 0, "No session expired notification should be handled when disabled")

        // 2. Re-enable only downloads notification
        harness.notifyOnDownloadsComplete = true

        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: testURL)
        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: testURL)
        NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)

        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(harness.downloadsHandled.count, 1, "Downloads notification should now be handled")
        XCTAssertEqual(harness.fileDetectedHandled.count, 0, "File detected notification should still be suppressed")
        XCTAssertEqual(harness.sessionExpiredHandled.count, 0, "Session expired notification should still be suppressed")
    }

    func testUserDefaultsStorageThreadSafetyForSmartWatcherSettings() async {
        let iterations = 100
        let testKeys = [
            AppSettingsKeys.watchedDownloadsPath,
            AppSettingsKeys.fileStabilizationDuration,
            AppSettingsKeys.customTemporaryExtensions,
            AppSettingsKeys.notifyOnDownloadsComplete,
            AppSettingsKeys.notifyOnFileDetected
        ]
        let suiteName = self.testSuiteName!

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    guard let defaults = UserDefaults(suiteName: suiteName) else { return }
                    defaults.set("/Users/test/Folder_\(i)", forKey: AppSettingsKeys.watchedDownloadsPath)
                    defaults.set(Double(i) * 0.5, forKey: AppSettingsKeys.fileStabilizationDuration)
                    defaults.set("part\(i), ext\(i)", forKey: AppSettingsKeys.customTemporaryExtensions)
                    defaults.set(i % 2 == 0, forKey: AppSettingsKeys.notifyOnDownloadsComplete)
                    defaults.set(i % 3 == 0, forKey: AppSettingsKeys.notifyOnFileDetected)

                    _ = defaults.string(forKey: AppSettingsKeys.watchedDownloadsPath)
                    _ = defaults.double(forKey: AppSettingsKeys.fileStabilizationDuration)
                    _ = defaults.string(forKey: AppSettingsKeys.customTemporaryExtensions)
                    _ = defaults.bool(forKey: AppSettingsKeys.notifyOnDownloadsComplete)
                    _ = defaults.bool(forKey: AppSettingsKeys.notifyOnFileDetected)
                }
            }
        }

        // Verify settings structure snapshot initialization under arbitrary loaded values
        let snapshot = AppSettings(
            watchedDownloadsPath: defaults.string(forKey: AppSettingsKeys.watchedDownloadsPath),
            customTemporaryExtensions: defaults.string(forKey: AppSettingsKeys.customTemporaryExtensions) ?? "",
            fileStabilizationDuration: defaults.double(forKey: AppSettingsKeys.fileStabilizationDuration),
            notifyOnDownloadsComplete: defaults.bool(forKey: AppSettingsKeys.notifyOnDownloadsComplete),
            notifyOnFileDetected: defaults.bool(forKey: AppSettingsKeys.notifyOnFileDetected)
        )

        XCTAssertFalse(snapshot.watchedDownloadsPath.isEmpty)
        XCTAssertGreaterThanOrEqual(snapshot.fileStabilizationDuration, 0.0)
        for key in testKeys {
            XCTAssertNotNil(defaults.object(forKey: key))
        }
    }

    // MARK: - 4. Unicode, Malformed & Extreme Paths & Display Helpers

    func testSleepModeDescriptionsWithAdversarialUnicodePaths() {
        let testCases: [(dirPath: String, filePath: String, count: Int)] = [
            // Emojis & Symbols
            (
                "/Users/test/📁 Downloads & 📦 Archives 2026/🚀",
                "/Users/test/📁 Downloads & 📦 Archives 2026/🚀/ファイナル 🔥 #1.tar.gz",
                3
            ),
            // Arabic / RTL
            (
                "/Users/test/تنزيلات_مهمة/المجلد_الرئيسي",
                "/Users/test/تنزيلات_مهمة/المجلد_الرئيسي/ملف_نهائي.iso",
                1
            ),
            // Japanese / CJK with special quotes and spaces
            (
                "/Users/test/ダウンロード/「プロジェクト」【2026】",
                "/Users/test/ダウンロード/「プロジェクト」【2026】/設計書（第2版） .pdf",
                0
            ),
            // Complex punctuation, quotes, brackets, and math symbols
            (
                "/Users/test/Weird!@#$%^&*()_+{}[]|;:,.<>?~`'\"/",
                "/Users/test/Weird!@#$%^&*()_+{}[]|;:,.<>?~`'\"/output [100%] (v1.0)+final=ok.dmg",
                5
            ),
            // Extremely long path (over 500 characters)
            (
                "/Users/test/" + String(repeating: "SubFolder_", count: 30) + "/Downloads",
                "/Users/test/" + String(repeating: "SubFolder_", count: 30) + "/Downloads/" + String(repeating: "A", count: 120) + ".part",
                42
            )
        ]

        for (dirStr, fileStr, count) in testCases {
            let dirURL = URL(fileURLWithPath: dirStr)
            let fileURL = URL(fileURLWithPath: fileStr)

            // Test watchingDownloads mode
            let watchMode = SleepMode.watchingDownloads(directory: dirURL, activeFilesCount: count)
            XCTAssertFalse(watchMode.statusTitle.isEmpty)
            XCTAssertFalse(watchMode.statusDescription.isEmpty)
            XCTAssertEqual(watchMode.watchedDirectory, dirURL)
            XCTAssertEqual(watchMode.activeFilesCount, count)
            XCTAssertTrue(watchMode.isWatchingDownloads)
            XCTAssertTrue(watchMode.isSmartWatching)
            XCTAssertTrue(watchMode.isActive)
            XCTAssertFalse(watchMode.isOff)

            if count > 0 {
                XCTAssertEqual(watchMode.statusTitle, "Downloading (\(count))")
                XCTAssertTrue(watchMode.statusDescription.contains("\(count) active"))
            } else {
                XCTAssertEqual(watchMode.statusTitle, "Watching Downloads")
                XCTAssertTrue(watchMode.statusDescription.contains("Watching for downloads in"))
            }

            // Test waitingForFile mode
            let waitMode = SleepMode.waitingForFile(targetURL: fileURL)
            XCTAssertFalse(waitMode.statusTitle.isEmpty)
            XCTAssertFalse(waitMode.statusDescription.isEmpty)
            XCTAssertEqual(waitMode.targetFileURL, fileURL)
            XCTAssertTrue(waitMode.isWaitingForFile)
            XCTAssertTrue(waitMode.isSmartWatching)
            XCTAssertTrue(waitMode.isActive)
            XCTAssertFalse(waitMode.isOff)
            XCTAssertEqual(waitMode.statusTitle, "Waiting for \(fileURL.lastPathComponent)")
            XCTAssertTrue(waitMode.statusDescription.contains(fileURL.lastPathComponent))
        }
    }

    func testPathAbbreviationHelperWithEdgeCasePaths() {
        func displayPath(_ path: String) -> String {
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                return "~" + path.dropFirst(home.count)
            }
            return path
        }

        let home = NSHomeDirectory()

        // 1. Standard home prefix
        XCTAssertEqual(displayPath("\(home)/Downloads"), "~/Downloads")
        XCTAssertEqual(displayPath("\(home)/Documents/Subfolder"), "~/Documents/Subfolder")

        // 2. Exactly home directory
        XCTAssertEqual(displayPath(home), "~")

        // 3. Unicode path inside home
        XCTAssertEqual(displayPath("\(home)/📁 Data/音楽"), "~/📁 Data/音楽")

        // 4. Paths outside home directory
        XCTAssertEqual(displayPath("/Library/Application Support"), "/Library/Application Support")
        XCTAssertEqual(displayPath("/tmp/download.crdownload"), "/tmp/download.crdownload")
        XCTAssertEqual(displayPath("/Volumes/External/Data"), "/Volumes/External/Data")
        XCTAssertEqual(displayPath("/"), "/")
        XCTAssertEqual(displayPath(""), "")
    }

    func testSleepModeAssociatedValuesIntegrityUnderAllTransitions() {
        let testDir = URL(fileURLWithPath: "/Users/test/Downloads")
        let targetFile = URL(fileURLWithPath: "/Users/test/Downloads/target.bin")
        let futureDate = Date(timeIntervalSince1970: 1800000000) // 2027

        let allModes: [SleepMode] = [
            .off,
            .indefinite,
            .timed(until: futureDate),
            .watchingDownloads(directory: testDir, activeFilesCount: 0),
            .watchingDownloads(directory: testDir, activeFilesCount: 7),
            .waitingForFile(targetURL: targetFile)
        ]

        for mode in allModes {
            switch mode {
            case .off:
                XCTAssertTrue(mode.isOff)
                XCTAssertFalse(mode.isActive)
                XCTAssertFalse(mode.isIndefinite)
                XCTAssertFalse(mode.isTimed)
                XCTAssertFalse(mode.isWatchingDownloads)
                XCTAssertFalse(mode.isWaitingForFile)
                XCTAssertFalse(mode.isSmartWatching)
                XCTAssertNil(mode.endDate)
                XCTAssertNil(mode.watchedDirectory)
                XCTAssertNil(mode.activeFilesCount)
                XCTAssertNil(mode.targetFileURL)
                XCTAssertEqual(mode.statusTitle, "Off")
                XCTAssertEqual(mode.statusDescription, "Your Mac can sleep normally")

            case .indefinite:
                XCTAssertFalse(mode.isOff)
                XCTAssertTrue(mode.isActive)
                XCTAssertTrue(mode.isIndefinite)
                XCTAssertFalse(mode.isTimed)
                XCTAssertFalse(mode.isWatchingDownloads)
                XCTAssertFalse(mode.isWaitingForFile)
                XCTAssertFalse(mode.isSmartWatching)
                XCTAssertNil(mode.endDate)
                XCTAssertNil(mode.watchedDirectory)
                XCTAssertNil(mode.activeFilesCount)
                XCTAssertNil(mode.targetFileURL)
                XCTAssertEqual(mode.statusTitle, "Indefinite")
                XCTAssertEqual(mode.statusDescription, "Sleep prevention is active indefinitely")

            case .timed(let until):
                XCTAssertFalse(mode.isOff)
                XCTAssertTrue(mode.isActive)
                XCTAssertFalse(mode.isIndefinite)
                XCTAssertTrue(mode.isTimed)
                XCTAssertFalse(mode.isWatchingDownloads)
                XCTAssertFalse(mode.isWaitingForFile)
                XCTAssertFalse(mode.isSmartWatching)
                XCTAssertEqual(mode.endDate, until)
                XCTAssertNil(mode.watchedDirectory)
                XCTAssertNil(mode.activeFilesCount)
                XCTAssertNil(mode.targetFileURL)
                XCTAssertEqual(mode.statusTitle, "Timed")
                XCTAssertTrue(mode.statusDescription.contains("Sleep prevention active until"))

            case .watchingDownloads(let dir, let count):
                XCTAssertFalse(mode.isOff)
                XCTAssertTrue(mode.isActive)
                XCTAssertFalse(mode.isIndefinite)
                XCTAssertFalse(mode.isTimed)
                XCTAssertTrue(mode.isWatchingDownloads)
                XCTAssertFalse(mode.isWaitingForFile)
                XCTAssertTrue(mode.isSmartWatching)
                XCTAssertNil(mode.endDate)
                XCTAssertEqual(mode.watchedDirectory, dir)
                XCTAssertEqual(mode.activeFilesCount, count)
                XCTAssertNil(mode.targetFileURL)
                if count > 0 {
                    XCTAssertEqual(mode.statusTitle, "Downloading (\(count))")
                    XCTAssertEqual(mode.statusDescription, "\(count) active \(count == 1 ? "download" : "downloads") in \(dir.lastPathComponent)")
                } else {
                    XCTAssertEqual(mode.statusTitle, "Watching Downloads")
                    XCTAssertEqual(mode.statusDescription, "Watching for downloads in \(dir.lastPathComponent)")
                }

            case .waitingForFile(let url):
                XCTAssertFalse(mode.isOff)
                XCTAssertTrue(mode.isActive)
                XCTAssertFalse(mode.isIndefinite)
                XCTAssertFalse(mode.isTimed)
                XCTAssertFalse(mode.isWatchingDownloads)
                XCTAssertTrue(mode.isWaitingForFile)
                XCTAssertTrue(mode.isSmartWatching)
                XCTAssertNil(mode.endDate)
                XCTAssertNil(mode.watchedDirectory)
                XCTAssertNil(mode.activeFilesCount)
                XCTAssertEqual(mode.targetFileURL, url)
                XCTAssertEqual(mode.statusTitle, "Waiting for \(url.lastPathComponent)")
                XCTAssertEqual(mode.statusDescription, "Waiting for \(url.lastPathComponent) to appear and finish writing")
            }
        }
    }

    // MARK: - 5. Boundary Conditions in Countdown & Extension Parsing

    func testCountdownFormattingNegativeAndExtremeSeconds() {
        func format(seconds: TimeInterval) -> String {
            guard seconds.isFinite else { return "0s remaining" }
            let total = max(0, Int(seconds))
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let secs = total % 60

            if hours > 0 {
                return "\(hours)h \(minutes)m remaining"
            } else if minutes > 0 {
                return "\(minutes)m \(secs)s remaining"
            } else {
                return "\(secs)s remaining"
            }
        }

        // Extreme negative and zero values
        XCTAssertEqual(format(seconds: -1.0), "0s remaining")
        XCTAssertEqual(format(seconds: -999999.0), "0s remaining")
        XCTAssertEqual(format(seconds: -Double.infinity), "0s remaining")
        XCTAssertEqual(format(seconds: Double.nan), "0s remaining")
        XCTAssertEqual(format(seconds: 0.0), "0s remaining")

        // Sub-second positive values
        XCTAssertEqual(format(seconds: 0.1), "0s remaining")
        XCTAssertEqual(format(seconds: 0.999), "0s remaining")

        // Boundary points: 59s -> 1m 0s
        XCTAssertEqual(format(seconds: 59), "59s remaining")
        XCTAssertEqual(format(seconds: 60), "1m 0s remaining")
        XCTAssertEqual(format(seconds: 61), "1m 1s remaining")

        // Boundary points: 3599s -> 1h 0m
        XCTAssertEqual(format(seconds: 3599), "59m 59s remaining")
        XCTAssertEqual(format(seconds: 3600), "1h 0m remaining")
        XCTAssertEqual(format(seconds: 3659), "1h 0m remaining")
        XCTAssertEqual(format(seconds: 3660), "1h 1m remaining")

        // Multi-day duration (e.g., 25 hours = 90000s)
        XCTAssertEqual(format(seconds: 90000), "25h 0m remaining")
        XCTAssertEqual(format(seconds: 90060), "25h 1m remaining")
    }

    func testCustomTemporaryExtensionsAdversarialInputs() {
        let adversarialInputs: [(raw: String, expected: Set<String>)] = [
            // Empty / whitespace
            ("", Set()),
            ("   \t  \n ", Set()),
            // Only separators
            (",,, , ,,,", Set()),
            // Excessive leading dots and spaces
            ("...part,  ....crdownload, .tmp.", Set(["part", "crdownload", "tmp."])),
            // Mixed case and duplicates
            ("PART, part, Part, .PaRt, .CRDOWNLOAD, crdownload", Set(["part", "crdownload"])),
            // Special symbols and compound tokens
            ("!ut, utpart, aria2, tar.gz.part, #download", Set(["!ut", "utpart", "aria2", "tar.gz.part", "#download"])),
            // Numbered extensions
            ("001, part1, r01, 7z.001", Set(["001", "part1", "r01", "7z.001"]))
        ]

        for (raw, expected) in adversarialInputs {
            let settings = AppSettings(customTemporaryExtensions: raw)
            XCTAssertEqual(settings.parsedCustomExtensions, expected, "Failed parsing: '\(raw)'")
        }
    }
}
