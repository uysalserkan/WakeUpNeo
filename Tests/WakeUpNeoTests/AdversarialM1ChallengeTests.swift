import XCTest
import Darwin
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

final class AdversarialM1ChallengeTests: XCTestCase {
    
    var tempDir: TestTempDirectory!
    var watcher: DefaultFileWatcherService!
    
    override func setUp() async throws {
        try await super.setUp()
        tempDir = try TestTempDirectory(prefix: "AdversarialM1ChallengeTests")
        watcher = DefaultFileWatcherService()
    }
    
    override func tearDown() async throws {
        watcher.stop()
        tempDir.cleanup()
        try await super.tearDown()
    }
    
    // MARK: - 1. Adversarial Pattern Matching & Extension Normalization
    
    func testComprehensiveEdgeCaseExtensions() {
        // Compound extensions
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.tar.gz.part"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "bundle.pkg.crdownload"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "image.iso.download"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "video.mp4.tmp"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "database.sqlite.partial"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "dist.tar.bz2.aria2"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "linux.raw.!ut"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "firmware.bin.utpart"))
        
        // Negative test cases (temporary extension not at suffix or stem)
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "crdownload.txt"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "part.zip"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "download.pdf"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "tmp.log"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "partial.json"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "aria2.conf"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "!ut.dat"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "utpart.bak"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.crdownload.zip"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "video.part.mp4"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.download.dmg"))
        
        // Exact names without prefix
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: ".crdownload"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: ".part"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: ".download"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "crdownload"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "part"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "download"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: ""))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "   "))
        
        // Trailing dot edge case
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.crdownload."))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.part.."))
    }
    
    func testCasingVariations() {
        let cases = [
            "FILE.CRDOWNLOAD",
            "file.CrDoWnLoAd",
            "ARCHIVE.PART",
            "archive.Part",
            "BUNDLE.DOWNLOAD",
            "bundle.DownLoad",
            "TEMP.TMP",
            "data.Tmp",
            "DATA.PARTIAL",
            "ISO.ARIA2",
            "TORRENT.!UT",
            "TORRENT.!Ut",
            "PAYLOAD.UTPART",
            "payload.UtPart"
        ]
        
        for name in cases {
            XCTAssertTrue(
                DownloadPatternMatcher.isTemporaryDownload(fileName: name),
                "Failed matching for cased filename '\(name)'"
            )
        }
    }
    
    func testWhitespaceAndTrailingSlashes() {
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "  archive.crdownload  "))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "/path/to/downloads/archive.crdownload/"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "downloads/archive.part///"))
    }
    
    func testUnicodeAndSpecialCharacters() {
        let specialNames = [
            "🚀 Görev Raporu 2026 #1 (Son Sürüm).crdownload",
            "日本語_テスト_ダウンロード.part",
            "café_au_lait_menu_2026.download",
            "文件_下载_v1.0.0.tmp",
            "Special [!@#$%^&*()_+] Chars.aria2",
            "Ümlaut_Ö_Ä_İ_Ş_Ç.utpart"
        ]
        
        for name in specialNames {
            XCTAssertTrue(
                DownloadPatternMatcher.isTemporaryDownload(fileName: name),
                "Failed unicode/special character matching for '\(name)'"
            )
        }
    }
    
    func testCustomExtensionEdgeCases() {
        let custom: Set<String> = [
            "  .CUSTOM  ",
            "..doubleDot",
            "UPPERCASE",
            "",
            "   ",
            "tar.gz"
        ]
        
        let effective = DownloadPatternMatcher.effectiveExtensions(customExtensions: custom)
        XCTAssertTrue(effective.contains("custom"))
        XCTAssertTrue(effective.contains("doubledot"))
        XCTAssertTrue(effective.contains("uppercase"))
        XCTAssertTrue(effective.contains("tar.gz"))
        XCTAssertFalse(effective.contains(""))
        
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.custom", customExtensions: custom))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.DOUBLEdot", customExtensions: custom))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.UPPERCASE", customExtensions: custom))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.tar.gz", customExtensions: custom))
    }
    
    // MARK: - 2. Safari .download Directory Bundles
    
    func testSafariDownloadDirectoryBundleStructure() throws {
        // Create Safari style .download directory bundle with internal files
        let safariBundle = try tempDir.createDownloadPackage(
            named: "macOS_Sonoma_14.5.download",
            files: [
                "Info.plist": Data("<plist version=\"1.0\"><dict><key>URL</key><string>https://apple.com</string></dict></plist>".utf8),
                "data.tmp": Data(repeating: 0xAA, count: 4096),
                ".DS_Store": Data([0x00, 0x01]),
                "Sub/nested.bin": Data([0xDE, 0xAD, 0xBE, 0xEF])
            ]
        )
        
        // Check pattern matcher
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(url: safariBundle))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "macOS_Sonoma_14.5.download"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "macOS_Sonoma_14.5.download/"))
        
        let active = DownloadPatternMatcher.activeDownloads(in: tempDir.url)
        XCTAssertEqual(active, ["macOS_Sonoma_14.5.download"])
    }
    
    // MARK: - 3. Zero-Byte Download File Handling
    
    func testZeroByteDownloadDetectionAndRemoval() async throws {
        // Create 0-byte download placeholder
        try tempDir.createFile(named: "initial_zero_byte.crdownload", contents: Data())
        
        let updateCount = SafeBox<Int>(0)
        let completeExpectation = expectation(description: "Zero byte download completes when renamed")
        
        try watcher.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { state in
                updateCount.set(updateCount.get + 1)
            },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        XCTAssertTrue(watcher.isWatching)
        try await Task.sleep(for: .milliseconds(200))
        
        // Rename zero-byte download to final
        try tempDir.renameFile(from: "initial_zero_byte.crdownload", to: "ready.txt")
        
        await fulfillment(of: [completeExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    // MARK: - 4. Burst File Churn Under Monitoring
    
    func testBurstFileChurnDoesNotCrashOrDeadlock() async throws {
        let updateCount = SafeBox<Int>(0)
        let completeExpectation = expectation(description: "Watcher completes after churn settles and download completes")
        
        // Start watching directory
        try watcher.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { state in
                updateCount.set(updateCount.get + 1)
            },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Error during burst churn: \(error)")
            }
        )
        
        // Generate a burst of 100 rapid file system mutations (creations, edits, deletions of non-download and download files)
        for i in 1...50 {
            try tempDir.createFile(named: "temp_noise_\(i).log", text: "noise \(i)")
            if i % 5 == 0 {
                try tempDir.removeFile(named: "temp_noise_\(i).log")
            }
        }
        
        // Introduce active download in the middle of churn
        try tempDir.createFile(named: "churn_target.part", text: "churn payload")
        
        for i in 51...100 {
            try tempDir.createFile(named: "temp_noise_\(i).log", text: "more noise \(i)")
            if i % 3 == 0 {
                try tempDir.removeFile(named: "temp_noise_\(i).log")
            }
        }
        
        // Wait for debounce to process churn
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(watcher.isWatching)
        
        // Finish the download
        try tempDir.removeFile(named: "churn_target.part")
        try tempDir.createFile(named: "churn_target.zip", text: "done")
        
        await fulfillment(of: [completeExpectation], timeout: 4.0)
        XCTAssertFalse(watcher.isWatching)
        XCTAssertGreaterThan(updateCount.get, 0)
    }
    
    // MARK: - 5. Multiple In-Flight Downloads Life Cycle
    
    func testMultipleInFlightDownloadsCompleteSequentially() async throws {
        let initialFiles = ["download_A.crdownload", "download_B.part", "download_C.download", "download_D.tmp"]
        for name in initialFiles {
            try tempDir.createFile(named: name, text: "payload for \(name)")
        }
        
        let lastObservedActiveCount = SafeBox<Int>(4)
        let completeExpectation = expectation(description: "Completion fires only after all 4 downloads finish")
        
        try watcher.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { state in
                lastObservedActiveCount.set(state.activeDownloads.count)
            },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(watcher.isWatching)
        
        // Remove files one by one with delays
        for (index, name) in initialFiles.enumerated() {
            try tempDir.removeFile(named: name)
            try await Task.sleep(for: .milliseconds(150))
            if index < initialFiles.count - 1 {
                XCTAssertTrue(watcher.isWatching, "Watcher completed prematurely while \(initialFiles.count - index - 1) downloads remained!")
            }
        }
        
        await fulfillment(of: [completeExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    // MARK: - 6. Rapid Multi-Threaded Start / Stop Cycles
    
    func testRapidConcurrentStartStopStress() async throws {
        let iterations = 30
        let targetURL = tempDir.url
        let errors = SafeBox<[Error]>([])
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let service = DefaultFileWatcherService()
                    do {
                        try service.watchDownloads(
                            in: targetURL,
                            temporaryExtensions: ["crdownload", "part"],
                            onUpdate: { _ in },
                            onComplete: { },
                            onError: { err in
                                let curr = errors.get
                                errors.set(curr + [err])
                            }
                        )
                        
                        if i % 2 == 0 {
                            try? await Task.sleep(for: .milliseconds(Int.random(in: 1...5)))
                        }
                        
                        service.stop()
                        XCTAssertFalse(service.isWatching)
                    } catch {
                        let curr = errors.get
                        errors.set(curr + [error])
                    }
                }
            }
        }
        
        XCTAssertTrue(errors.get.isEmpty, "Encountered unexpected errors during start/stop: \(errors.get)")
    }
    
    func testSingleInstanceRapidStartStopIdempotence() throws {
        for _ in 1...20 {
            try watcher.watchDownloads(
                in: tempDir.url,
                temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
                onUpdate: { _ in },
                onComplete: { },
                onError: { _ in }
            )
            XCTAssertTrue(watcher.isWatching)
            watcher.stop()
            XCTAssertFalse(watcher.isWatching)
        }
    }
}
