import XCTest
@testable import WakeUpNeoCore

// MARK: - SettingsTests
//
// Tests the model layer: SleepMode, DefaultDuration, and AppSettings.
// No UI, no services — pure value-type logic.

final class SettingsTests: XCTestCase {

    // MARK: - SleepMode

    func testSleepModeIsOff() {
        XCTAssertTrue(SleepMode.off.isOff)
        XCTAssertFalse(SleepMode.indefinite.isOff)
        XCTAssertFalse(SleepMode.timed(until: .now).isOff)
    }

    func testSleepModeIsActive() {
        XCTAssertFalse(SleepMode.off.isActive)
        XCTAssertTrue(SleepMode.indefinite.isActive)
        XCTAssertTrue(SleepMode.timed(until: .now).isActive)
    }

    func testSleepModeIsIndefinite() {
        XCTAssertFalse(SleepMode.off.isIndefinite)
        XCTAssertTrue(SleepMode.indefinite.isIndefinite)
        XCTAssertFalse(SleepMode.timed(until: .now).isIndefinite)
    }

    func testSleepModeEndDate() {
        let date = Date(timeIntervalSinceNow: 3600)
        XCTAssertNil(SleepMode.off.endDate)
        XCTAssertNil(SleepMode.indefinite.endDate)
        XCTAssertEqual(SleepMode.timed(until: date).endDate, date)
    }

    func testSleepModeEquality() {
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = Date(timeIntervalSince1970: 2_000_000)

        XCTAssertEqual(SleepMode.off, .off)
        XCTAssertEqual(SleepMode.indefinite, .indefinite)
        XCTAssertEqual(SleepMode.timed(until: d1), .timed(until: d1))

        XCTAssertNotEqual(SleepMode.off, .indefinite)
        XCTAssertNotEqual(SleepMode.timed(until: d1), .timed(until: d2))
        XCTAssertNotEqual(SleepMode.indefinite, .timed(until: d1))
    }

    // MARK: - DefaultDuration

    func testDefaultDurationRawValues() {
        XCTAssertEqual(DefaultDuration.fifteenMinutes.rawValue, 900)
        XCTAssertEqual(DefaultDuration.thirtyMinutes.rawValue,  1_800)
        XCTAssertEqual(DefaultDuration.oneHour.rawValue,        3_600)
        XCTAssertEqual(DefaultDuration.twoHours.rawValue,       7_200)
    }

    func testDefaultDurationShortLabels() {
        XCTAssertEqual(DefaultDuration.fifteenMinutes.shortLabel, "15m")
        XCTAssertEqual(DefaultDuration.thirtyMinutes.shortLabel,  "30m")
        XCTAssertEqual(DefaultDuration.oneHour.shortLabel,        "1h")
        XCTAssertEqual(DefaultDuration.twoHours.shortLabel,       "2h")
    }

    func testDefaultDurationLongLabels() {
        XCTAssertEqual(DefaultDuration.fifteenMinutes.label, "15 minutes")
        XCTAssertEqual(DefaultDuration.thirtyMinutes.label,  "30 minutes")
        XCTAssertEqual(DefaultDuration.oneHour.label,        "1 hour")
        XCTAssertEqual(DefaultDuration.twoHours.label,       "2 hours")
    }

    func testDefaultDurationCaseIterableCount() {
        XCTAssertEqual(DefaultDuration.allCases.count, 4,
            "There should be exactly 4 preset durations")
    }

    func testDefaultDurationIdentifiable() {
        // id must be unique across all cases
        let ids = DefaultDuration.allCases.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count, "Each DefaultDuration must have a unique id")
    }

    func testDefaultDurationRoundTripThroughRawValue() {
        for preset in DefaultDuration.allCases {
            let recovered = DefaultDuration(rawValue: preset.rawValue)
            XCTAssertEqual(recovered, preset,
                "RawValue round-trip should recover the original preset for \(preset.label)")
        }
    }

    // MARK: - SleepMode: Smart Watcher Extensions

    func testSleepModeSmartWatcherBooleans() {
        let dummyURL = URL(fileURLWithPath: "/tmp/Downloads")
        let fileURL = URL(fileURLWithPath: "/tmp/Downloads/output.iso")

        let downloadMode = SleepMode.watchingDownloads(directory: dummyURL, activeFilesCount: 2)
        let fileMode = SleepMode.waitingForFile(targetURL: fileURL)

        XCTAssertFalse(downloadMode.isOff)
        XCTAssertTrue(downloadMode.isActive)
        XCTAssertFalse(downloadMode.isIndefinite)
        XCTAssertFalse(downloadMode.isTimed)
        XCTAssertTrue(downloadMode.isWatchingDownloads)
        XCTAssertFalse(downloadMode.isWaitingForFile)
        XCTAssertTrue(downloadMode.isSmartWatching)
        XCTAssertEqual(downloadMode.watchedDirectory, dummyURL)
        XCTAssertEqual(downloadMode.activeFilesCount, 2)
        XCTAssertNil(downloadMode.targetFileURL)

        XCTAssertFalse(fileMode.isOff)
        XCTAssertTrue(fileMode.isActive)
        XCTAssertFalse(fileMode.isIndefinite)
        XCTAssertFalse(fileMode.isTimed)
        XCTAssertFalse(fileMode.isWatchingDownloads)
        XCTAssertTrue(fileMode.isWaitingForFile)
        XCTAssertTrue(fileMode.isSmartWatching)
        XCTAssertNil(fileMode.watchedDirectory)
        XCTAssertNil(fileMode.activeFilesCount)
        XCTAssertEqual(fileMode.targetFileURL, fileURL)
    }

    func testSleepModeFormatters() {
        let dir = URL(fileURLWithPath: "/Users/test/Downloads")
        let file = URL(fileURLWithPath: "/Users/test/Downloads/report.pdf")

        let zeroDownloads = SleepMode.watchingDownloads(directory: dir, activeFilesCount: 0)
        XCTAssertEqual(zeroDownloads.statusTitle, "Watching Downloads")
        XCTAssertTrue(zeroDownloads.statusDescription.contains("Watching for downloads in Downloads"))

        let twoDownloads = SleepMode.watchingDownloads(directory: dir, activeFilesCount: 2)
        XCTAssertEqual(twoDownloads.statusTitle, "Downloading (2)")
        XCTAssertTrue(twoDownloads.statusDescription.contains("2 active downloads in Downloads"))

        let waiting = SleepMode.waitingForFile(targetURL: file)
        XCTAssertEqual(waiting.statusTitle, "Waiting for report.pdf")
        XCTAssertTrue(waiting.statusDescription.contains("Waiting for report.pdf"))

        let proc = SleepMode.watchingProcess(pid: 1234, name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        XCTAssertEqual(proc.statusTitle, "Watching Xcode (1234)")
        XCTAssertTrue(proc.statusDescription.contains("Watching Xcode (PID 1234)"))
        XCTAssertTrue(proc.isWatchingProcess)
        XCTAssertTrue(proc.isSmartWatching)
        XCTAssertEqual(proc.watchedPID, 1234)
        XCTAssertEqual(proc.watchedProcessName, "Xcode")
        XCTAssertEqual(proc.watchedBundleIdentifier, "com.apple.dt.Xcode")
    }

    // MARK: - AppSettings

    func testAppSettingsDefaultValues() {
        let s = AppSettings.default
        XCTAssertTrue(s.launchAtLogin,            "Default: launch at login ON")
        XCTAssertTrue(s.showCountdownInMenuBar,   "Default: show countdown ON")
        XCTAssertEqual(s.defaultDuration, .oneHour, "Default duration: 1 hour")
        XCTAssertTrue(s.notifyOnSessionEnd,       "Default: notify on end ON")
        XCTAssertFalse(s.notifyOnSessionExpiring, "Default: notify expiring OFF")
        XCTAssertTrue(s.preventSystemSleep,       "Default: prevent system sleep ON")
        XCTAssertFalse(s.keepDisplayAwake,        "Default: keep display awake OFF")
        XCTAssertFalse(s.preventLidSleep,          "Default: prevent lid sleep OFF")
        XCTAssertEqual(s.watchedDownloadsPath, AppSettings.defaultDownloadsURL.path(percentEncoded: false))
        XCTAssertEqual(s.customTemporaryExtensions, "")
        XCTAssertEqual(s.fileStabilizationDuration, 2.0)
        XCTAssertTrue(s.notifyOnDownloadsComplete)
        XCTAssertTrue(s.notifyOnFileDetected)
        XCTAssertTrue(s.notifyOnProcessTerminated)
    }

    func testAppSettingsEquality() {
        let a = AppSettings.default
        var b = AppSettings.default
        XCTAssertEqual(a, b)

        b.keepDisplayAwake = true
        XCTAssertNotEqual(a, b)

        var c = AppSettings.default
        c.customTemporaryExtensions = "xyz"
        XCTAssertNotEqual(a, c)

        var d = AppSettings.default
        d.preventLidSleep = true
        XCTAssertNotEqual(a, d)

        var e = AppSettings.default
        e.notifyOnProcessTerminated = false
        XCTAssertNotEqual(a, e)
    }

    func testAppSettingsKeysAreNonEmpty() {
        XCTAssertFalse(AppSettingsKeys.launchAtLogin.isEmpty)
        XCTAssertFalse(AppSettingsKeys.showCountdownInMenuBar.isEmpty)
        XCTAssertFalse(AppSettingsKeys.defaultDuration.isEmpty)
        XCTAssertFalse(AppSettingsKeys.notifyOnSessionEnd.isEmpty)
        XCTAssertFalse(AppSettingsKeys.notifyOnSessionExpiring.isEmpty)
        XCTAssertFalse(AppSettingsKeys.preventSystemSleep.isEmpty)
        XCTAssertFalse(AppSettingsKeys.keepDisplayAwake.isEmpty)
        XCTAssertFalse(AppSettingsKeys.preventLidSleep.isEmpty)
        XCTAssertFalse(AppSettingsKeys.watchedDownloadsPath.isEmpty)
        XCTAssertFalse(AppSettingsKeys.customTemporaryExtensions.isEmpty)
        XCTAssertFalse(AppSettingsKeys.fileStabilizationDuration.isEmpty)
        XCTAssertFalse(AppSettingsKeys.notifyOnDownloadsComplete.isEmpty)
        XCTAssertFalse(AppSettingsKeys.notifyOnFileDetected.isEmpty)
        XCTAssertFalse(AppSettingsKeys.notifyOnProcessTerminated.isEmpty)
    }

    func testAppSettingsKeysAreUnique() {
        let keys = [
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
            AppSettingsKeys.notifyOnProcessTerminated
        ]
        let unique = Set(keys)
        XCTAssertEqual(keys.count, unique.count, "All UserDefaults keys must be unique")
    }

    func testAppSettingsCustomExtensionsParsing() {
        var s = AppSettings.default
        s.customTemporaryExtensions = " .part, CRDOWNLOAD , , .mypart "
        let parsed = s.parsedCustomExtensions
        XCTAssertEqual(parsed, ["part", "crdownload", "mypart"])
    }
}
