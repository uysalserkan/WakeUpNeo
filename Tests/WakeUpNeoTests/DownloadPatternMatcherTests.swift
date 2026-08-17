import XCTest
@testable import WakeUpNeoCore

final class DownloadPatternMatcherTests: XCTestCase {
    
    var tempDir: TestTempDirectory!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = try TestTempDirectory(prefix: "DownloadPatternMatcherTests")
    }
    
    override func tearDownWithError() throws {
        tempDir?.cleanup()
        try super.tearDownWithError()
    }
    
    // MARK: - Tier 1: Pattern Matching & Extension Classification
    
    func testDefaultBrowserExtensionsMatch() {
        let testCases: [String: Bool] = [
            "installer.crdownload": true,
            "archive.part": true,
            "movie.download": true,
            "data.tmp": true,
            "backup.partial": true,
            "linux.iso.aria2": true,
            "dist.tar.!ut": true,
            "video.utpart": true,
            "document.pdf": false,
            "app.dmg": false,
            "source.zip": false,
            "notes.txt": false
        ]
        
        for (filename, expected) in testCases {
            XCTAssertEqual(
                DownloadPatternMatcher.isTemporaryDownload(fileName: filename),
                expected,
                "Failed matching for '\(filename)'"
            )
        }
    }
    
    func testCaseInsensitiveMatching() {
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "MOVIE.CRDOWNLOAD"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "Archive.Part"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "Safari.DownLoad"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "DATA.TMP"))
    }
    
    func testCustomExtensionsAdditionAndNormalization() {
        let custom: Set<String> = [".mypart", "CUSTOMEXT", "  .dl  "]
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.mypart", customExtensions: custom))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.customext", customExtensions: custom))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.dl", customExtensions: custom))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.crdownload", customExtensions: custom))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "file.pdf", customExtensions: custom))
    }
    
    func testCompoundExtensions() {
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.tar.gz.crdownload"))
        XCTAssertFalse(DownloadPatternMatcher.isTemporaryDownload(fileName: "archive.crdownload.zip"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "my.file.with.dots.part"))
    }
    
    func testFilenamesWithSpacesAndUnicode() {
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "Yıllık Rapor 2026 📊.crdownload"))
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(fileName: "Document Final v2 (1).part"))
    }
    
    func testActiveDownloadsScanningWithMixedFiles() throws {
        try tempDir.createFile(named: "ready.pdf", text: "pdf")
        try tempDir.createFile(named: "image.png", text: "png")
        try tempDir.createFile(named: "in_progress.crdownload", text: "downloading")
        try tempDir.createFile(named: "another.part", text: "downloading")
        
        let active = DownloadPatternMatcher.activeDownloads(in: tempDir.url)
        XCTAssertEqual(active, ["another.part", "in_progress.crdownload"])
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases
    
    func testSafariDownloadPackageDirectoryDetection() throws {
        let packageDir = try tempDir.createDownloadPackage(
            named: "Xcode_16.download",
            files: ["Info.plist": Data("plist".utf8), "data": Data([0x01, 0x02])]
        )
        
        XCTAssertTrue(DownloadPatternMatcher.isTemporaryDownload(url: packageDir))
        let active = DownloadPatternMatcher.activeDownloads(in: tempDir.url)
        XCTAssertEqual(active, ["Xcode_16.download"])
    }
    
    func testZeroByteTemporaryDownloadFileDetection() throws {
        try tempDir.createFile(named: "empty_placeholder.crdownload", contents: Data())
        let active = DownloadPatternMatcher.activeDownloads(in: tempDir.url)
        XCTAssertEqual(active, ["empty_placeholder.crdownload"])
    }
    
    func testEmptyDirectoryOrNonExistentReturnsEmpty() {
        let empty = DownloadPatternMatcher.activeDownloads(in: tempDir.url)
        XCTAssertTrue(empty.isEmpty)
        
        let nonExistent = tempDir.url.appendingPathComponent("does_not_exist")
        let nonExistentActive = DownloadPatternMatcher.activeDownloads(in: nonExistent)
        XCTAssertTrue(nonExistentActive.isEmpty)
    }
}
