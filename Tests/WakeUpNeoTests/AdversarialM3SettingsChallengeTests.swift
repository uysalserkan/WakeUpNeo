import XCTest
import Foundation
@testable import WakeUpNeoCore

// MARK: - AdversarialM3SettingsChallengeTests
//
// Empirical Adversarial Challenger Test Suite for Milestone 3 (Settings & Persistence):
// 1. Custom Extensions Edge Cases:
//    - Empty strings, whitespace-only, repeated commas, multiple leading dots, dot suffixes.
//    - Mixed casing, non-ASCII Unicode (Cyrillic, CJK, accents, emojis).
//    - Extremely long strings (10k+ characters, thousands of tokens).
//    - Double extensions and punctuation-heavy extension patterns.
// 2. Settle Duration Edge Cases:
//    - Negative, zero, extreme durations (10,000s), Double.nan, Double.infinity.
//    - Stepper boundaries (0.5s to 30.0s), fractional rounding, formatting strings.
// 3. Path Resolution Edge Cases:
//    - Non-existent paths, file paths in place of directory paths.
//    - Symlinks (valid directory symlinks, file symlinks, broken symlinks, resolved vs raw).
//    - Directory packages (.download bundle) aggregate size & metadata.
//    - Paths with spaces, emojis, Unicode symbols, percent-encoding roundtrips.
// 4. Concurrency & Thread-Safety:
//    - Concurrent `AppSettings.load()` and `UserDefaults` updates across multiple tasks.
//    - Sendable struct isolation and mutation across tasks.
//    - Multi-threaded `DownloadPatternMatcher` and `FileStabilityChecker` stress.

final class AdversarialM3SettingsChallengeTests: XCTestCase {

    private var testSuiteName: String!
    private var testDefaults: UserDefaults!
    private var tempDir: TestTempDirectory!

    override func setUp() async throws {
        try await super.setUp()
        testSuiteName = "com.wakeupneo.tests.adversarial.m3.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        tempDir = try TestTempDirectory(prefix: "AdvM3Settings")
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        tempDir.cleanup()
        try await super.tearDown()
    }

    // MARK: - 1. Custom Extensions Edge Cases

    func testCustomExtensionsEmptyAndWhitespaceOnly() {
        let emptyInputs = [
            "",
            "   ",
            "\t\n\r",
            " , , , ",
            ",,,,,",
            "\n,\t, \r,   ",
            "   ,,,\t\t,,   "
        ]

        for input in emptyInputs {
            let settings = AppSettings(customTemporaryExtensions: input)
            let parsed = settings.parsedCustomExtensions
            XCTAssertTrue(
                parsed.isEmpty,
                "Input '\(input.debugDescription)' must yield empty set of parsed extensions, got: \(parsed)"
            )

            // Verify effective extensions falls back strictly to defaultExtensions
            let effective = DownloadPatternMatcher.effectiveExtensions(customExtensions: parsed)
            XCTAssertEqual(effective, DownloadPatternMatcher.defaultExtensions)
        }
    }

    func testCustomExtensionsMultipleDotsAndSpecialPunctuation() {
        let input = ".crdownload, ..part, ...tmp, .download., ....partial, !ut, #custom, @download, .tar.gz"
        let settings = AppSettings(customTemporaryExtensions: input)
        let parsed = settings.parsedCustomExtensions

        // All leading dots stripped and lowercased
        XCTAssertTrue(parsed.contains("crdownload"))
        XCTAssertTrue(parsed.contains("part"))
        XCTAssertTrue(parsed.contains("tmp"))
        XCTAssertTrue(parsed.contains("download."))
        XCTAssertTrue(parsed.contains("partial"))
        XCTAssertTrue(parsed.contains("!ut"))
        XCTAssertTrue(parsed.contains("#custom"))
        XCTAssertTrue(parsed.contains("@download"))
        XCTAssertTrue(parsed.contains("tar.gz"))

        // Matching checks
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.tar.gz", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "image.iso.part", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "data.download.", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.!ut", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.#custom", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.@download", customExtensions: parsed))
    }

    func testCustomExtensionsMixedCasingAndNormalization() {
        let input = " .CRDOWNLOAD, .PaRt,  .DoWnLoAd  ,  .XyZ_TeMp123  , .!UT "
        let settings = AppSettings(customTemporaryExtensions: input)
        let parsed = settings.parsedCustomExtensions

        let expected: Set<String> = ["crdownload", "part", "download", "xyz_temp123", "!ut"]
        XCTAssertEqual(parsed, expected)

        // Case-insensitive matching verification
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "VIDEO.CRDOWNLOAD", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.PART", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "BUNDLE.DOWNLOAD", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "data.XYZ_TEMP123", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "torrent.!UT", customExtensions: parsed))
    }

    func testCustomExtensionsNonASCIIAndUnicode() {
        // Cyrillic (загрузка), Korean (다운로드), Japanese (一時), German umlaut (vorläufig), emoji (🚀part)
        let unicodeInput = ".загрузка, .다운로드, .一時, .vorläufig, .🚀part, .résumé"
        let settings = AppSettings(customTemporaryExtensions: unicodeInput)
        let parsed = settings.parsedCustomExtensions

        XCTAssertTrue(parsed.contains("загрузка"))
        XCTAssertTrue(parsed.contains("다운로드"))
        XCTAssertTrue(parsed.contains("一時"))
        XCTAssertTrue(parsed.contains("vorläufig"))
        XCTAssertTrue(parsed.contains("🚀part"))
        XCTAssertTrue(parsed.contains("résumé"))

        // Matching files with Unicode extensions
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "документ.pdf.загрузка", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "영상.mp4.다운로드", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "データ.zip.一時", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "bericht.docx.vorläufig", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "backup.tar.🚀part", customExtensions: parsed))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "cv.pdf.résumé", customExtensions: parsed))

        // Non-matching regular files
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "документ.pdf", customExtensions: parsed))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "영상.mp4", customExtensions: parsed))
    }

    func testCustomExtensionsExtremelyLongStringsAndThousandsOfTokens() {
        // Generate a 15,000-character string containing 1,000 distinct comma-separated extensions
        var tokens = [String]()
        for i in 0..<1000 {
            tokens.append(".ext_\(i)_" + String(repeating: "x", count: 10))
        }
        let hugeInput = tokens.joined(separator: ", ")

        let startTime = CFAbsoluteTimeGetCurrent()
        let settings = AppSettings(customTemporaryExtensions: hugeInput)
        let parsed = settings.parsedCustomExtensions
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertEqual(parsed.count, 1000, "Should parse all 1,000 distinct extensions")
        XCTAssertLessThan(duration, 0.5, "Parsing 1,000 extensions should complete in under 500ms")

        // Check lookup speed with large custom extension set
        let checkStart = CFAbsoluteTimeGetCurrent()
        let isTemp = DownloadPatternMatcher.isTemporaryDownload(
            fileName: "large_download.iso.ext_999_xxxxxxxxxx",
            customExtensions: parsed
        )
        let checkDuration = CFAbsoluteTimeGetCurrent() - checkStart

        XCTAssertTrue(isTemp)
        XCTAssertLessThan(checkDuration, 0.05, "Extension matching should be O(1) set lookup")
    }

    func testCustomExtensionsExtremelyLongSingleToken() {
        // Single 5,000-character extension string
        let longExt = String(repeating: "a", count: 5000)
        let settings = AppSettings(customTemporaryExtensions: ".\(longExt)")
        let parsed = settings.parsedCustomExtensions

        XCTAssertEqual(parsed, [longExt])
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "test.\(longExt)", customExtensions: parsed))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "test.different", customExtensions: parsed))
    }

    // MARK: - 2. Settle Duration Edge Cases

    func testSettleDurationNegativeAndZeroClampingInChecker() {
        // AppSettings stores raw Double
        let negativeSettings = AppSettings(fileStabilizationDuration: -10.0)
        XCTAssertEqual(negativeSettings.fileStabilizationDuration, -10.0)

        let zeroSettings = AppSettings(fileStabilizationDuration: 0.0)
        XCTAssertEqual(zeroSettings.fileStabilizationDuration, 0.0)

        // FileStabilityChecker defensively clamps to minimum 0.1s
        let checkerNegative = FileStabilityChecker(stabilizationDuration: -10.0)
        XCTAssertEqual(checkerNegative.stabilizationDuration, 0.1, "Negative duration must be clamped to 0.1s")

        let checkerZero = FileStabilityChecker(stabilizationDuration: 0.0)
        XCTAssertEqual(checkerZero.stabilizationDuration, 0.1, "Zero duration must be clamped to 0.1s")
    }

    func testSettleDurationExtremePositiveValues() {
        let extremeSettings = AppSettings(fileStabilizationDuration: 10_000.0)
        XCTAssertEqual(extremeSettings.fileStabilizationDuration, 10_000.0)

        let checkerExtreme = FileStabilityChecker(stabilizationDuration: 10_000.0)
        XCTAssertEqual(checkerExtreme.stabilizationDuration, 10_000.0)

        // Evaluate file stability with extreme window
        let testFile = tempDir.url.appendingPathComponent("huge_wait.iso")
        _ = try? tempDir.createFile(named: "huge_wait.iso", text: "initial")

        let t0 = Date.now
        let state1 = checkerExtreme.evaluate(at: testFile, now: t0)
        XCTAssertTrue(state1.exists)

        // After 100 seconds (still far less than 10,000s)
        let t1 = t0.addingTimeInterval(100)
        let state2 = checkerExtreme.evaluate(at: testFile, now: t1)
        XCTAssertTrue(state2.exists)
        XCTAssertTrue(state2.isStabilizing, "Must still be stabilizing when elapsed time (100s) < 10000s")

        // After 10,001 seconds
        let t2 = t0.addingTimeInterval(10001)
        let state3 = checkerExtreme.evaluate(at: testFile, now: t2)
        XCTAssertTrue(state3.exists)
        XCTAssertFalse(state3.isStabilizing, "Must be stabilized after 10,001s >= 10,000s")
    }

    func testSettleDurationNaNAndInfinityHandling() {
        let nanChecker = FileStabilityChecker(stabilizationDuration: .nan)
        // Ensure instantiation does not crash or throw
        XCTAssertFalse(nanChecker.stabilizationDuration.isSignalingNaN)

        let infChecker = FileStabilityChecker(stabilizationDuration: .infinity)
        XCTAssertTrue(infChecker.stabilizationDuration.isInfinite)

        let testFile = tempDir.url.appendingPathComponent("inf_wait.iso")
        _ = try? tempDir.createFile(named: "inf_wait.iso", text: "hello")

        let t0 = Date.now
        let stateInf1 = infChecker.evaluate(at: testFile, now: t0)
        XCTAssertTrue(stateInf1.exists)

        // Even after 1,000,000 seconds, infinity is never reached
        let stateInf2 = infChecker.evaluate(at: testFile, now: t0.addingTimeInterval(1_000_000))
        XCTAssertTrue(stateInf2.isStabilizing, "Infinity stabilization window should remain stabilizing")
    }

    func testSettleDurationStepperBoundaryAndFormatting() {
        // UI Range is 0.5s to 30.0s in 0.5s increments
        var current = 0.5
        var steps = [Double]()
        while current <= 30.0001 {
            steps.append(current)
            let formatted = String(format: "%.1f s", current)
            XCTAssertFalse(formatted.isEmpty)
            XCTAssertTrue(formatted.hasSuffix(" s"))

            let accessibilityValue = String(format: "%.1f seconds", current)
            XCTAssertTrue(accessibilityValue.hasSuffix(" seconds"))

            current += 0.5
        }

        XCTAssertEqual(steps.count, 60, "Expected 60 steps between 0.5s and 30.0s (inclusive)")
        XCTAssertEqual(steps.first, 0.5)
        XCTAssertEqual(steps.last! >= 29.9 && steps.last! <= 30.1, true)
    }

    // MARK: - 3. Path Resolution Edge Cases

    func testPathResolutionNonExistentPaths() {
        let nonExistentPath = "/private/tmp/does_not_exist_\(UUID().uuidString)/nonexistent_dir"
        let nonExistentURL = URL(fileURLWithPath: nonExistentPath)

        let settings = AppSettings(watchedDownloadsPath: nonExistentPath)
        XCTAssertEqual(settings.watchedDownloadsPath, nonExistentPath)
        XCTAssertEqual(settings.watchedDownloadsURL, nonExistentURL)

        // 1. activeDownloads on non-existent directory returns empty list, does not throw/crash
        let active = DownloadPatternMatcher.activeDownloads(in: nonExistentURL)
        XCTAssertEqual(active, [])

        // 2. readMetadata on non-existent file returns exists = false
        let meta = FileStabilityChecker.readMetadata(at: nonExistentURL)
        XCTAssertFalse(meta.exists)
        XCTAssertEqual(meta.size, 0)
        XCTAssertNil(meta.modificationDate)

        // 3. evaluate on non-existent target returns exists = false, isStabilizing = false
        let checker = FileStabilityChecker(stabilizationDuration: 2.0)
        let state = checker.evaluate(at: nonExistentURL)
        XCTAssertFalse(state.exists)
        XCTAssertFalse(state.isStabilizing)
        XCTAssertEqual(state.currentSize, 0)
    }

    func testPathResolutionSymlinkToDirectory() throws {
        // Create real folder with download file
        let realFolder = tempDir.url.appendingPathComponent("RealTargetFolder")
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
        let downloadFile = realFolder.appendingPathComponent("archive.zip.crdownload")
        try "payload".write(to: downloadFile, atomically: true, encoding: .utf8)

        // Create symlink pointing to RealTargetFolder
        let symlinkFolder = tempDir.url.appendingPathComponent("SymlinkFolder")
        try FileManager.default.createSymbolicLink(at: symlinkFolder, withDestinationURL: realFolder)

        // Verify activeDownloads follows directory when symlink is resolved
        let resolvedSymlink = symlinkFolder.resolvingSymlinksInPath()
        let activeFromSymlink = DownloadPatternMatcher.activeDownloads(in: resolvedSymlink)
        XCTAssertEqual(activeFromSymlink, ["archive.zip.crdownload"])
    }

    func testPathResolutionSymlinkToTargetFile() throws {
        // Create real target file
        let realFile = tempDir.url.appendingPathComponent("real_video.mp4")
        let content = "video_stream_content_12345"
        try content.write(to: realFile, atomically: true, encoding: .utf8)

        // Create symlink pointing to realFile
        let symlinkFile = tempDir.url.appendingPathComponent("symlink_video.mp4")
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: realFile)

        // Verify readMetadata resolves symlink and reads target file size
        let resolvedURL = symlinkFile.resolvingSymlinksInPath()
        let metaResolved = FileStabilityChecker.readMetadata(at: resolvedURL)
        XCTAssertTrue(metaResolved.exists)
        XCTAssertEqual(metaResolved.size, Int64(content.utf8.count))
        XCTAssertNotNil(metaResolved.modificationDate)

        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let state = checker.evaluate(at: resolvedURL)
        XCTAssertTrue(state.exists)
        XCTAssertEqual(state.currentSize, Int64(content.utf8.count))

        // Direct symlink without resolving also does not crash and reports valid metadata
        let directMeta = FileStabilityChecker.readMetadata(at: symlinkFile)
        XCTAssertTrue(directMeta.exists)
        XCTAssertGreaterThan(directMeta.size, 0)
    }

    func testPathResolutionBrokenSymlink() throws {
        let nonExistentTarget = tempDir.url.appendingPathComponent("ghost_file.bin")
        let brokenSymlink = tempDir.url.appendingPathComponent("broken_link.bin")
        try FileManager.default.createSymbolicLink(at: brokenSymlink, withDestinationURL: nonExistentTarget)

        // Verify broken symlink handled gracefully
        let meta = FileStabilityChecker.readMetadata(at: brokenSymlink)
        XCTAssertFalse(meta.exists)
        XCTAssertEqual(meta.size, 0)
        XCTAssertNil(meta.modificationDate)

        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let state = checker.evaluate(at: brokenSymlink)
        XCTAssertFalse(state.exists)
        XCTAssertFalse(state.isStabilizing)
    }

    func testPathResolutionSpacesEmojisAndUnicodeCharacters() throws {
        let complexSubdir = tempDir.url.appendingPathComponent("🚀 Downloads & 特殊文字 (2026) #1")
        try FileManager.default.createDirectory(at: complexSubdir, withIntermediateDirectories: true)

        let complexFilePath = complexSubdir.appendingPathComponent("🎵 My Song [Final 100%].flac.part")
        try "audio_data".write(to: complexFilePath, atomically: true, encoding: .utf8)

        // Path round-trip test (normalizing directory paths)
        let rawPath = complexSubdir.path(percentEncoded: false)
        let settings = AppSettings(watchedDownloadsPath: rawPath)
        XCTAssertEqual(settings.watchedDownloadsPath, rawPath)
        XCTAssertEqual(
            settings.watchedDownloadsURL.standardizedFileURL.path(percentEncoded: false),
            complexSubdir.standardizedFileURL.path(percentEncoded: false)
        )

        // Active downloads scanner in Unicode path
        let active = DownloadPatternMatcher.activeDownloads(in: complexSubdir)
        XCTAssertEqual(active, ["🎵 My Song [Final 100%].flac.part"])

        // File stability evaluator on Unicode target file
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let state = checker.evaluate(at: complexFilePath)
        XCTAssertTrue(state.exists)
        XCTAssertEqual(state.currentSize, Int64("audio_data".utf8.count))
    }

    func testPathResolutionDirectoryPackageMetadataAggregation() throws {
        // Test package folder (e.g. Safari package bundle "installer.download/")
        let packageURL = tempDir.url.appendingPathComponent("installer.download")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let subfile1 = packageURL.appendingPathComponent("part1.bin")
        let subfile2 = packageURL.appendingPathComponent("part2.bin")
        try "chunk1_1000".write(to: subfile1, atomically: true, encoding: .utf8)
        try "chunk2_2000_extra".write(to: subfile2, atomically: true, encoding: .utf8)

        let expectedSize = Int64("chunk1_1000".utf8.count + "chunk2_2000_extra".utf8.count)

        let meta = FileStabilityChecker.readMetadata(at: packageURL)
        XCTAssertTrue(meta.exists)
        XCTAssertEqual(meta.size, expectedSize, "Directory package size must be aggregate sum of contained files")
        XCTAssertNotNil(meta.modificationDate)

        // Also test pattern matcher classifies .download directory as temporary
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(url: packageURL))
    }

    func testPathResolutionWatchedPathIsRegularFileInsteadOfDirectory() throws {
        let regularFile = tempDir.url.appendingPathComponent("not_a_dir.txt")
        try "content".write(to: regularFile, atomically: true, encoding: .utf8)

        let settings = AppSettings(watchedDownloadsPath: regularFile.path(percentEncoded: false))
        XCTAssertEqual(settings.watchedDownloadsURL, regularFile)

        // Scanning a regular file as a directory should return empty list gracefully
        let downloads = DownloadPatternMatcher.activeDownloads(in: regularFile)
        XCTAssertEqual(downloads, [])
    }

    func testPathResolutionIgnoredFiles() throws {
        // System and ignored files inside watched directory
        let ignoredNames = [".DS_Store", ".localized", ".", ".."]
        for name in ignoredNames where name != "." && name != ".." {
            let fileURL = tempDir.url.appendingPathComponent(name)
            try "meta".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Add 1 real download file
        try tempDir.createFile(named: "real.crdownload", text: "data")

        let active = DownloadPatternMatcher.activeDownloads(in: tempDir.url)
        XCTAssertEqual(active, ["real.crdownload"], "Ignored system files must not be included in active downloads")
    }

    // MARK: - 4. Concurrency & Multi-Thread Stress

    func testConcurrentAppSettingsLoadAndUserDefaultsWrites() async throws {
        let suiteName: String = testSuiteName
        let iterations = 200

        // Concurrently write to UserDefaults while reading AppSettings
        await withTaskGroup(of: Void.self) { group in
            // Writer task
            group.addTask {
                guard let suite = UserDefaults(suiteName: suiteName) else { return }
                for i in 0..<iterations {
                    suite.set(i % 2 == 0, forKey: AppSettingsKeys.launchAtLogin)
                    suite.set(i % 2 == 1, forKey: AppSettingsKeys.preventSystemSleep)
                    suite.set(Double(i % 30) + 0.5, forKey: AppSettingsKeys.fileStabilizationDuration)
                    suite.set("ext_\(i)", forKey: AppSettingsKeys.customTemporaryExtensions)
                    suite.set("/tmp/path_\(i)", forKey: AppSettingsKeys.watchedDownloadsPath)
                }
            }

            // Reader tasks
            for _ in 0..<5 {
                group.addTask {
                    guard let suite = UserDefaults(suiteName: suiteName) else { return }
                    for _ in 0..<iterations {
                        let raw = suite.double(forKey: AppSettingsKeys.defaultDuration)
                        let path = suite.string(forKey: AppSettingsKeys.watchedDownloadsPath) ?? AppSettings.defaultDownloadsURL.path(percentEncoded: false)
                        let customExt = suite.string(forKey: AppSettingsKeys.customTemporaryExtensions) ?? ""
                        let settle = suite.object(forKey: AppSettingsKeys.fileStabilizationDuration) == nil ? 2.0 : suite.double(forKey: AppSettingsKeys.fileStabilizationDuration)

                        let snapshot = AppSettings(
                            launchAtLogin: suite.bool(forKey: AppSettingsKeys.launchAtLogin),
                            showCountdownInMenuBar: suite.bool(forKey: AppSettingsKeys.showCountdownInMenuBar),
                            defaultDuration: DefaultDuration(rawValue: raw) ?? .oneHour,
                            notifyOnSessionEnd: suite.bool(forKey: AppSettingsKeys.notifyOnSessionEnd),
                            notifyOnSessionExpiring: suite.bool(forKey: AppSettingsKeys.notifyOnSessionExpiring),
                            preventSystemSleep: suite.bool(forKey: AppSettingsKeys.preventSystemSleep),
                            keepDisplayAwake: suite.bool(forKey: AppSettingsKeys.keepDisplayAwake),
                            preventLidSleep: suite.bool(forKey: AppSettingsKeys.preventLidSleep),
                            watchedDownloadsPath: path,
                            customTemporaryExtensions: customExt,
                            fileStabilizationDuration: settle,
                            notifyOnDownloadsComplete: suite.bool(forKey: AppSettingsKeys.notifyOnDownloadsComplete),
                            notifyOnFileDetected: suite.bool(forKey: AppSettingsKeys.notifyOnFileDetected)
                        )

                        _ = snapshot.watchedDownloadsURL
                        _ = snapshot.parsedCustomExtensions
                    }
                }
            }
        }
    }

    func testConcurrentAppSettingsStructMutationAndValueSemantics() async {
        let base = AppSettings.default

        await withTaskGroup(of: AppSettings.self) { group in
            for i in 0..<100 {
                group.addTask {
                    var local = base
                    local.fileStabilizationDuration = Double(i) + 0.5
                    local.customTemporaryExtensions = "ext_\(i), part"
                    local.keepDisplayAwake = (i % 2 == 0)
                    local.watchedDownloadsPath = "/tmp/dir_\(i)"
                    return local
                }
            }

            var count = 0
            for await item in group {
                XCTAssertFalse(item.parsedCustomExtensions.isEmpty)
                XCTAssertGreaterThan(item.fileStabilizationDuration, 0)
                count += 1
            }
            XCTAssertEqual(count, 100)
        }

        // Base must remain untouched (value type isolation)
        XCTAssertEqual(base, AppSettings.default)
    }

    func testConcurrentPatternMatcherEvaluations() async {
        let fileNames = [
            "installer.pkg.crdownload",
            "video.mp4.part",
            "bundle.download",
            "document.pdf",
            "archive.tar.gz",
            "temporary.tmp",
            "image.iso.aria2",
            "torrent.file.!ut",
            "test.utpart",
            "regular_file.txt"
        ]

        let customSets: [Set<String>] = [
            ["crdownload", "part"],
            ["custom1", "custom2", "download"],
            ["tmp", "aria2", "!ut"],
            Set((0..<50).map { "ext_\($0)" })
        ]

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let name = fileNames[i % fileNames.count]
                    let customs = customSets[i % customSets.count]
                    _ = DownloadPatternMatcher.isTemporaryDownload(fileName: name, customExtensions: customs)
                    _ = DownloadPatternMatcher.normalizeExtension(".TEST_\(i)")
                    _ = DownloadPatternMatcher.effectiveExtensions(customExtensions: customs)
                }
            }
        }
    }

    func testConcurrentFileStabilityCheckerEvaluationAndReset() async throws {
        let targetFile = tempDir.url.appendingPathComponent("concurrent_target.bin")
        try "initial_data_payload".write(to: targetFile, atomically: true, encoding: .utf8)

        let checker = FileStabilityChecker(stabilizationDuration: 1.0)

        await withTaskGroup(of: Void.self) { group in
            // Concurrent evaluate tasks
            for i in 0..<40 {
                group.addTask {
                    let now = Date.now.addingTimeInterval(Double(i) * 0.1)
                    _ = checker.evaluate(at: targetFile, now: now)
                }
            }

            // Concurrent reset tasks
            for _ in 0..<10 {
                group.addTask {
                    checker.reset()
                }
            }
        }

        // Clean final evaluation
        let finalState = checker.evaluate(at: targetFile)
        XCTAssertTrue(finalState.exists)
        XCTAssertEqual(finalState.currentSize, Int64("initial_data_payload".utf8.count))
    }
}
