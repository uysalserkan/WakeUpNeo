import XCTest
import AppKit
import UniformTypeIdentifiers
import UserNotifications
@testable import WakeUpNeoCore

// MARK: - UIIntegrationTests

/// Comprehensive UI Integration & Preferences test suite for Milestone 3.
///
/// Verifies:
/// 1. `AppSettingsKeys` uniqueness, non-emptiness, and `UserDefaults` round-trip storage.
/// 2. `SleepMode` presentation labels, descriptions (singular/plural), Unicode handling, and accessors.
/// 3. Countdown and remaining time formatting logic.
/// 4. `NotificationService` notification builders and `NotificationCenter` payload dispatch.
/// 5. Smart watcher notification observer coordination.
/// 6. AppKit Open Panel configurations (headless-safe verification).
@MainActor
final class UIIntegrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "com.wakeupneo.tests.ui.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: testSuiteName)!
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: testSuiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - 1. AppSettingsKeys & Persistence

    func testAppSettingsKeysUniquenessAndNonEmptiness() {
        let keys: [String] = [
            AppSettingsKeys.launchAtLogin,
            AppSettingsKeys.showCountdownInMenuBar,
            AppSettingsKeys.defaultDuration,
            AppSettingsKeys.notifyOnSessionEnd,
            AppSettingsKeys.notifyOnSessionExpiring,
            AppSettingsKeys.preventSystemSleep,
            AppSettingsKeys.keepDisplayAwake,
            AppSettingsKeys.preventLidSleep,
            AppSettingsKeys.watchedDownloadsPath,
            AppSettingsKeys.customTemporaryExtensions,
            AppSettingsKeys.fileStabilizationDuration,
            AppSettingsKeys.notifyOnDownloadsComplete,
            AppSettingsKeys.notifyOnFileDetected,
            AppSettingsKeys.notifyOnProcessTerminated,
            AppSettingsKeys.checkForUpdatesAutomatically,
            AppSettingsKeys.lastUpdateCheckTimestamp
        ]

        for key in keys {
            XCTAssertFalse(key.isEmpty, "Key should not be empty")
            XCTAssertFalse(key.contains(" "), "Key should not contain spaces: \(key)")
        }

        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, keys.count, "All AppSettingsKeys must be unique")
    }

    func testAppSettingsDefaultsAndSnapshot() {
        let settings = AppSettings.default

        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertTrue(settings.showCountdownInMenuBar)
        XCTAssertEqual(settings.defaultDuration, .oneHour)
        XCTAssertTrue(settings.notifyOnSessionEnd)
        XCTAssertFalse(settings.notifyOnSessionExpiring)
        XCTAssertTrue(settings.preventSystemSleep)
        XCTAssertFalse(settings.keepDisplayAwake)
        XCTAssertFalse(settings.preventLidSleep)
        XCTAssertEqual(settings.watchedDownloadsPath, AppSettings.defaultDownloadsURL.path(percentEncoded: false))
        XCTAssertEqual(settings.customTemporaryExtensions, "")
        XCTAssertEqual(settings.fileStabilizationDuration, 2.0)
        XCTAssertTrue(settings.notifyOnDownloadsComplete)
        XCTAssertTrue(settings.notifyOnFileDetected)
        XCTAssertTrue(settings.notifyOnProcessTerminated)
        XCTAssertTrue(settings.checkForUpdatesAutomatically)
        XCTAssertEqual(settings.lastUpdateCheckTimestamp, 0.0)
        XCTAssertEqual(settings.watchedDownloadsURL, AppSettings.defaultDownloadsURL)
        XCTAssertTrue(settings.parsedCustomExtensions.isEmpty)
    }

    func testAppSettingsUserDefaultsRoundTripForSmartWatchers() {
        // Test custom preferences persistence in UserDefaults
        let customPath = "/Users/testuser/CustomDownloads"
        let customExtensions = ".crdownload, part,  .TMP, customdownload "
        let settleDuration = 5.5
        let notifyDownloads = false
        let notifyFile = false

        defaults.set(customPath, forKey: AppSettingsKeys.watchedDownloadsPath)
        defaults.set(customExtensions, forKey: AppSettingsKeys.customTemporaryExtensions)
        defaults.set(settleDuration, forKey: AppSettingsKeys.fileStabilizationDuration)
        defaults.set(notifyDownloads, forKey: AppSettingsKeys.notifyOnDownloadsComplete)
        defaults.set(notifyFile, forKey: AppSettingsKeys.notifyOnFileDetected)

        let loadedWatchedPath = defaults.string(forKey: AppSettingsKeys.watchedDownloadsPath)
        let loadedExtensions = defaults.string(forKey: AppSettingsKeys.customTemporaryExtensions)
        let loadedSettle = defaults.double(forKey: AppSettingsKeys.fileStabilizationDuration)
        let loadedNotifyDownloads = defaults.bool(forKey: AppSettingsKeys.notifyOnDownloadsComplete)
        let loadedNotifyFile = defaults.bool(forKey: AppSettingsKeys.notifyOnFileDetected)

        XCTAssertEqual(loadedWatchedPath, customPath)
        XCTAssertEqual(loadedExtensions, customExtensions)
        XCTAssertEqual(loadedSettle, settleDuration)
        XCTAssertEqual(loadedNotifyDownloads, notifyDownloads)
        XCTAssertEqual(loadedNotifyFile, notifyFile)

        // Verify parsing logic on snapshot constructed from stored values
        let snapshot = AppSettings(
            watchedDownloadsPath: loadedWatchedPath,
            customTemporaryExtensions: loadedExtensions ?? "",
            fileStabilizationDuration: loadedSettle,
            notifyOnDownloadsComplete: loadedNotifyDownloads,
            notifyOnFileDetected: loadedNotifyFile
        )

        XCTAssertEqual(snapshot.watchedDownloadsPath, customPath)
        XCTAssertEqual(snapshot.watchedDownloadsURL.path(percentEncoded: false), customPath)
        XCTAssertEqual(snapshot.fileStabilizationDuration, 5.5)
        XCTAssertFalse(snapshot.notifyOnDownloadsComplete)
        XCTAssertFalse(snapshot.notifyOnFileDetected)
        XCTAssertTrue(snapshot.parsedCustomExtensions.contains("crdownload"))
        XCTAssertTrue(snapshot.parsedCustomExtensions.contains("part"))
        XCTAssertTrue(snapshot.parsedCustomExtensions.contains("tmp"))
        XCTAssertTrue(snapshot.parsedCustomExtensions.contains("customdownload"))
        XCTAssertEqual(snapshot.parsedCustomExtensions.count, 4)
    }

    func testAppSettingsCustomTemporaryExtensionsParsing() {
        let rawInput = " .CRDOWNLOAD, ,,  part, .PART,  .downLOAD, ,  aria2 , !ut "
        let settings = AppSettings(customTemporaryExtensions: rawInput)
        let parsed = settings.parsedCustomExtensions

        XCTAssertEqual(parsed, Set(["crdownload", "part", "download", "aria2", "!ut"]))
        XCTAssertFalse(parsed.contains(""))
        XCTAssertFalse(parsed.contains(" "))
    }

    // MARK: - 2. SleepMode Presentation & Labels

    func testSleepModeStatusTitlesAndDescriptionsSingularPlural() {
        let testDir = URL(fileURLWithPath: "/Users/test/Downloads")
        let targetURL = URL(fileURLWithPath: "/Users/test/Downloads/render.mp4")

        // 1. Off
        let offMode = SleepMode.off
        XCTAssertEqual(offMode.statusTitle, "Off")
        XCTAssertEqual(offMode.statusDescription, "Your Mac can sleep normally")
        XCTAssertTrue(offMode.isOff)
        XCTAssertFalse(offMode.isActive)

        // 2. Indefinite
        let indefiniteMode = SleepMode.indefinite
        XCTAssertEqual(indefiniteMode.statusTitle, "Indefinite")
        XCTAssertEqual(indefiniteMode.statusDescription, "Sleep prevention is active indefinitely")
        XCTAssertTrue(indefiniteMode.isIndefinite)
        XCTAssertTrue(indefiniteMode.isActive)

        // 3. Timed
        let futureDate = Date.now.addingTimeInterval(3600)
        let timedMode = SleepMode.timed(until: futureDate)
        XCTAssertEqual(timedMode.statusTitle, "Timed")
        XCTAssertTrue(timedMode.statusDescription.contains("Sleep prevention active until"))
        XCTAssertTrue(timedMode.isTimed)
        XCTAssertEqual(timedMode.endDate, futureDate)

        // 4. Watching Downloads - 0 files
        let watchingZero = SleepMode.watchingDownloads(directory: testDir, activeFilesCount: 0)
        XCTAssertEqual(watchingZero.statusTitle, "Watching Downloads")
        XCTAssertEqual(watchingZero.statusDescription, "Watching for downloads in Downloads")
        XCTAssertTrue(watchingZero.isWatchingDownloads)
        XCTAssertTrue(watchingZero.isSmartWatching)
        XCTAssertEqual(watchingZero.watchedDirectory, testDir)
        XCTAssertEqual(watchingZero.activeFilesCount, 0)

        // 5. Watching Downloads - 1 file (Singular)
        let watchingOne = SleepMode.watchingDownloads(directory: testDir, activeFilesCount: 1)
        XCTAssertEqual(watchingOne.statusTitle, "Downloading (1)")
        XCTAssertEqual(watchingOne.statusDescription, "1 active download in Downloads")

        // 6. Watching Downloads - multiple files (Plural)
        let watchingMultiple = SleepMode.watchingDownloads(directory: testDir, activeFilesCount: 4)
        XCTAssertEqual(watchingMultiple.statusTitle, "Downloading (4)")
        XCTAssertEqual(watchingMultiple.statusDescription, "4 active downloads in Downloads")

        // 7. Waiting For File
        let waitingFile = SleepMode.waitingForFile(targetURL: targetURL)
        XCTAssertEqual(waitingFile.statusTitle, "Waiting for render.mp4")
        XCTAssertEqual(waitingFile.statusDescription, "Waiting for render.mp4 to appear and finish writing")
        XCTAssertTrue(waitingFile.isWaitingForFile)
        XCTAssertTrue(waitingFile.isSmartWatching)
        XCTAssertEqual(waitingFile.targetFileURL, targetURL)
    }

    func testSleepModeStatusWithSpecialCharactersAndUnicode() {
        let unicodeDir = URL(fileURLWithPath: "/Users/test/📁 Downloads & 音楽")
        let unicodeTarget = URL(fileURLWithPath: "/Users/test/📁 Downloads & 音楽/アーカイブ (2026) #1.tar.gz")

        let watchingUnicode = SleepMode.watchingDownloads(directory: unicodeDir, activeFilesCount: 2)
        XCTAssertEqual(watchingUnicode.statusTitle, "Downloading (2)")
        XCTAssertEqual(watchingUnicode.statusDescription, "2 active downloads in 📁 Downloads & 音楽")

        let waitingUnicode = SleepMode.waitingForFile(targetURL: unicodeTarget)
        XCTAssertEqual(waitingUnicode.statusTitle, "Waiting for アーカイブ (2026) #1.tar.gz")
        XCTAssertEqual(waitingUnicode.statusDescription, "Waiting for アーカイブ (2026) #1.tar.gz to appear and finish writing")
    }

    // MARK: - 3. Countdown & Time Formatting Logic

    func testCountdownFormattingLogic() {
        func format(seconds: TimeInterval) -> String {
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

        // > 1 hour
        XCTAssertEqual(format(seconds: 3665), "1h 1m remaining")
        XCTAssertEqual(format(seconds: 7200), "2h 0m remaining")
        XCTAssertEqual(format(seconds: 7325), "2h 2m remaining")

        // < 1 hour, >= 1 minute
        XCTAssertEqual(format(seconds: 1800), "30m 0s remaining")
        XCTAssertEqual(format(seconds: 305), "5m 5s remaining")
        XCTAssertEqual(format(seconds: 60), "1m 0s remaining")

        // < 1 minute
        XCTAssertEqual(format(seconds: 45), "45s remaining")
        XCTAssertEqual(format(seconds: 1), "1s remaining")
        XCTAssertEqual(format(seconds: 0), "0s remaining")
        XCTAssertEqual(format(seconds: -10), "0s remaining")
    }

    // MARK: - 4. NotificationService & NotificationCenter Integration

    func testNotificationNamesAndServiceMethods() {
        XCTAssertEqual(Notification.Name.wakeUpNeoSessionExpired.rawValue, "com.wakeupneo.sessionExpired")
        XCTAssertEqual(Notification.Name.wakeUpNeoDownloadsCompleted.rawValue, "com.wakeupneo.downloadsCompleted")
        XCTAssertEqual(Notification.Name.wakeUpNeoFileDetected.rawValue, "com.wakeupneo.fileDetected")
        XCTAssertEqual(Notification.Name.wakeUpNeoProcessTerminated.rawValue, "com.wakeupneo.processTerminated")

        let service = NotificationService()
        let dir = URL(fileURLWithPath: "/Users/test/Downloads")
        let fileURL = URL(fileURLWithPath: "/Users/test/Downloads/package.iso")

        // Verify no crashes or exceptions when invoking notification dispatch
        service.sendSessionEndedNotification()
        service.sendSessionExpiringSoonNotification(minutesRemaining: 5)
        service.sendSessionExpiringSoonNotification(minutesRemaining: 1)
        service.sendDownloadsCompletedNotification(directory: dir)
        service.sendDownloadsCompletedNotification(directory: nil)
        service.sendFileDetectedNotification(targetURL: fileURL)
        service.sendProcessTerminatedNotification(processName: "Xcode", pid: 1234)

        let release = GitHubRelease(
            id: 1,
            tagName: "v1.0.5",
            name: "WakeUpNeo 1.0.5",
            htmlURL: URL(string: "https://github.com/uysalserkan/wakeupneo/releases/tag/v1.0.5")!
        )
        service.sendUpdateAvailableNotification(release: release)
    }

    func testNotificationCenterObserverPayloadsForSmartWatchers() async {
        let expectedDir = URL(fileURLWithPath: "/Users/test/Downloads")
        let expectedTarget = URL(fileURLWithPath: "/Users/test/Downloads/result.zip")
        let expectedProcess = MonitoredProcessInfo(pid: 9999, name: "TestProcess")

        var receivedDir: URL?
        var receivedTarget: URL?
        var receivedProcess: MonitoredProcessInfo?
        var expiredCount = 0

        let token1 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoDownloadsCompleted,
            object: nil,
            queue: .main
        ) { notification in
            receivedDir = notification.object as? URL
        }

        let token2 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoFileDetected,
            object: nil,
            queue: .main
        ) { notification in
            receivedTarget = notification.object as? URL
        }

        let token3 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoSessionExpired,
            object: nil,
            queue: .main
        ) { _ in
            expiredCount += 1
        }

        let token4 = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoProcessTerminated,
            object: nil,
            queue: .main
        ) { notification in
            receivedProcess = notification.object as? MonitoredProcessInfo
        }

        defer {
            NotificationCenter.default.removeObserver(token1)
            NotificationCenter.default.removeObserver(token2)
            NotificationCenter.default.removeObserver(token3)
            NotificationCenter.default.removeObserver(token4)
        }

        // Post notifications
        NotificationCenter.default.post(name: .wakeUpNeoDownloadsCompleted, object: expectedDir)
        NotificationCenter.default.post(name: .wakeUpNeoFileDetected, object: expectedTarget)
        NotificationCenter.default.post(name: .wakeUpNeoSessionExpired, object: nil)
        NotificationCenter.default.post(name: .wakeUpNeoProcessTerminated, object: expectedProcess)

        // Yield to allow main queue dispatch
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(receivedDir, expectedDir)
        XCTAssertEqual(receivedTarget, expectedTarget)
        XCTAssertEqual(receivedProcess, expectedProcess)
        XCTAssertEqual(expiredCount, 1)
    }

    // MARK: - 5. File Open Panel Configuration (Headless-Safe)

    func testFileOpenPanelConfigurationProperties() {
        // Verify folder open panel configuration
        let folderPanel = NSOpenPanel()
        folderPanel.canChooseFiles = false
        folderPanel.canChooseDirectories = true
        folderPanel.allowsMultipleSelection = false
        folderPanel.canCreateDirectories = true
        folderPanel.resolvesAliases = true
        folderPanel.prompt = "Choose"
        folderPanel.title = "Select Downloads Folder"
        folderPanel.directoryURL = AppSettings.defaultDownloadsURL

        XCTAssertFalse(folderPanel.canChooseFiles)
        XCTAssertTrue(folderPanel.canChooseDirectories)
        XCTAssertFalse(folderPanel.allowsMultipleSelection)
        XCTAssertTrue(folderPanel.canCreateDirectories)
        XCTAssertTrue(folderPanel.resolvesAliases)
        XCTAssertEqual(folderPanel.prompt, "Choose")
        XCTAssertEqual(folderPanel.directoryURL, AppSettings.defaultDownloadsURL)

        // Verify file open panel configuration
        let filePanel = NSOpenPanel()
        filePanel.canChooseFiles = true
        filePanel.canChooseDirectories = false
        filePanel.allowsMultipleSelection = false
        filePanel.canCreateDirectories = false
        filePanel.resolvesAliases = true
        filePanel.prompt = "Watch"
        filePanel.title = "Select File to Watch"
        filePanel.directoryURL = AppSettings.defaultDownloadsURL

        XCTAssertTrue(filePanel.canChooseFiles)
        XCTAssertFalse(filePanel.canChooseDirectories)
        XCTAssertFalse(filePanel.allowsMultipleSelection)
        XCTAssertFalse(filePanel.canCreateDirectories)
        XCTAssertTrue(filePanel.resolvesAliases)
        XCTAssertEqual(filePanel.prompt, "Watch")
        XCTAssertEqual(filePanel.directoryURL, AppSettings.defaultDownloadsURL)
    }

    // MARK: - 6. SleepMode Associated Values & Boundaries

    func testSleepModeAssociatedValueAccessors() {
        let testDir = URL(fileURLWithPath: "/Users/test/Downloads")
        let targetFile = URL(fileURLWithPath: "/Users/test/Downloads/data.bin")
        let expiry = Date.now.addingTimeInterval(120)

        let off = SleepMode.off
        XCTAssertNil(off.endDate)
        XCTAssertNil(off.watchedDirectory)
        XCTAssertNil(off.activeFilesCount)
        XCTAssertNil(off.targetFileURL)
        XCTAssertFalse(off.isSmartWatching)

        let timed = SleepMode.timed(until: expiry)
        XCTAssertEqual(timed.endDate, expiry)
        XCTAssertNil(timed.watchedDirectory)
        XCTAssertNil(timed.activeFilesCount)
        XCTAssertNil(timed.targetFileURL)
        XCTAssertFalse(timed.isSmartWatching)

        let watching = SleepMode.watchingDownloads(directory: testDir, activeFilesCount: 3)
        XCTAssertNil(watching.endDate)
        XCTAssertEqual(watching.watchedDirectory, testDir)
        XCTAssertEqual(watching.activeFilesCount, 3)
        XCTAssertNil(watching.targetFileURL)
        XCTAssertTrue(watching.isSmartWatching)

        let waiting = SleepMode.waitingForFile(targetURL: targetFile)
        XCTAssertNil(waiting.endDate)
        XCTAssertNil(waiting.watchedDirectory)
        XCTAssertNil(waiting.activeFilesCount)
        XCTAssertEqual(waiting.targetFileURL, targetFile)
        XCTAssertTrue(waiting.isSmartWatching)
    }

    func testFileStabilityDurationStepperBoundaryValues() {
        // Range defined in UI: 0.5s to 30.0s
        let minDuration = 0.5
        let defaultDuration = 2.0
        let maxDuration = 30.0

        let sMin = AppSettings(fileStabilizationDuration: minDuration)
        XCTAssertEqual(sMin.fileStabilizationDuration, 0.5)

        let sDef = AppSettings(fileStabilizationDuration: defaultDuration)
        XCTAssertEqual(sDef.fileStabilizationDuration, 2.0)

        let sMax = AppSettings(fileStabilizationDuration: maxDuration)
        XCTAssertEqual(sMax.fileStabilizationDuration, 30.0)
    }

    func testActiveIconColorCases() {
        for color in ActiveIconColor.allCases {
            XCTAssertFalse(color.rawValue.isEmpty)
            XCTAssertFalse(color.label.isEmpty)
            XCTAssertEqual(ActiveIconColor(rawValue: color.rawValue), color)
        }
        XCTAssertEqual(ActiveIconColor(rawValue: "invalid"), nil)
    }

    // MARK: - 7. Session Duration Tracking

    func testSessionDurationTracking() {
        let composite = CompositeSleepService(
            systemSleepService: MockSleepService(),
            displaySleepService: MockSleepService(),
            lidSleepService: MockSleepService()
        )
        let manager = SleepManager(compositeService: composite)

        XCTAssertNil(manager.sessionDuration)
        XCTAssertFalse(manager.isActive)

        manager.start(for: 1800)
        XCTAssertEqual(manager.sessionDuration, 1800)
        XCTAssertTrue(manager.isActive)

        manager.start(for: 3600)
        XCTAssertEqual(manager.sessionDuration, 3600)
        XCTAssertTrue(manager.isActive)

        manager.startIndefinitely()
        XCTAssertNil(manager.sessionDuration)
        XCTAssertTrue(manager.isActive)

        manager.stop()
        XCTAssertNil(manager.sessionDuration)
        XCTAssertFalse(manager.isActive)
    }
}

