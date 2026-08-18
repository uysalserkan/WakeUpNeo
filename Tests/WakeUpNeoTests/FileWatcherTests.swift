import XCTest
@testable import WakeUpNeoCore

private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag: Bool
    
    init(_ flag: Bool = false) {
        self.flag = flag
    }
    
    func raiseOnce() -> Bool {
        lock.withLock {
            if !flag {
                flag = true
                return true
            }
            return false
        }
    }
}

private final class ThreadSafeBox<T>: @unchecked Sendable {
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


final class FileWatcherTests: XCTestCase {
    
    var tempDir: TestTempDirectory!
    var watcher: DefaultFileWatcherService!
    
    override func setUp() {
        super.setUp()
        tempDir = try! TestTempDirectory(prefix: "FileWatcherTests")
        watcher = DefaultFileWatcherService()
    }
    
    override func tearDown() {
        watcher?.stop()
        tempDir?.cleanup()
        super.tearDown()
    }
    
    // MARK: - Tier 1: Download Watching Lifecycle
    
    func testWatchDownloadsDetectsInitialActiveFilesAndCompletesOnRemoval() async throws {
        try tempDir.createFile(named: "download_1.crdownload", text: "chunk1")
        
        let updateExpectation = expectation(description: "Initial download update received")
        let completeExpectation = expectation(description: "Download completion triggered")
        
        try watcher.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { state in
                if state.activeDownloads == ["download_1.crdownload"] {
                    updateExpectation.fulfill()
                }
            },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        XCTAssertTrue(watcher.isWatching)
        await fulfillment(of: [updateExpectation], timeout: 2.0)
        
        // Simulate download finish (rename to final file)
        try tempDir.renameFile(from: "download_1.crdownload", to: "download_1.zip")
        
        await fulfillment(of: [completeExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testWatchDownloadsHandlesNewDownloadAppearingAndFinishing() async throws {
        let firstUpdate = expectation(description: "First update on empty dir")
        let downloadAppeared = expectation(description: "Download file appeared")
        let completeExpectation = expectation(description: "Download completed")
        
        let initialUpdateFlag = AtomicFlag()
        
        try watcher.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { state in
                if state.activeDownloads.isEmpty && !state.hasActiveDownloads {
                    if initialUpdateFlag.raiseOnce() {
                        firstUpdate.fulfill()
                    }
                } else if state.activeDownloads == ["report.part"] {
                    downloadAppeared.fulfill()
                }
            },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        await fulfillment(of: [firstUpdate], timeout: 2.0)
        
        // Start download
        try tempDir.createFile(named: "report.part", text: "downloading...")
        await fulfillment(of: [downloadAppeared], timeout: 2.0)
        
        // Finish download
        try tempDir.removeFile(named: "report.part")
        try tempDir.createFile(named: "report.pdf", text: "done")
        
        await fulfillment(of: [completeExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    // MARK: - Tier 1: Target File Waiting Lifecycle
    
    func testWaitForFileDetectsCreationAndStabilization() async throws {
        let targetURL = tempDir.url.appendingPathComponent("build_output.iso")
        let createdUpdate = expectation(description: "Target file created and stabilizing")
        let completeExpectation = expectation(description: "Target file stabilized")
        
        var createdFulfilled = false
        try watcher.waitForFile(
            at: targetURL,
            stabilizationDuration: 0.8,
            onUpdate: { state in
                if state.exists && state.isStabilizing && !createdFulfilled {
                    createdFulfilled = true
                    createdUpdate.fulfill()
                }
            },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        XCTAssertTrue(watcher.isWatching)
        
        // Create file
        try tempDir.createFile(named: "build_output.iso", text: "ISO Payload")
        await fulfillment(of: [createdUpdate], timeout: 2.0)
        
        // Wait for stabilization
        await fulfillment(of: [completeExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testWaitForFileFastPathPreExistingStableFile() async throws {
        let targetURL = tempDir.url.appendingPathComponent("ready_archive.zip")
        try tempDir.createFile(named: "ready_archive.zip", text: "archive content")
        let pastDate = Date.now.addingTimeInterval(-10)
        try FileManager.default.setAttributes([.modificationDate: pastDate], ofItemAtPath: targetURL.path(percentEncoded: false))
        
        let completeExpectation = expectation(description: "Pre-existing file immediately triggers complete")
        
        try watcher.waitForFile(
            at: targetURL,
            stabilizationDuration: 1.0,
            onUpdate: { _ in },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        await fulfillment(of: [completeExpectation], timeout: 2.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    // MARK: - Tier 2: Boundary & Corner Cases
    
    func testStopCancelsWatchingAndIsIdempotent() throws {
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
        
        // Repeated stops are safe
        watcher.stop()
        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testAlreadyWatchingThrowsError() throws {
        try watcher.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { _ in },
            onComplete: { },
            onError: { _ in }
        )
        
        XCTAssertThrowsError(
            try watcher.watchDownloads(
                in: tempDir.url,
                temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
                onUpdate: { _ in },
                onComplete: { },
                onError: { _ in }
            )
        ) { error in
            guard case FileWatcherError.alreadyWatching = error else {
                XCTFail("Expected FileWatcherError.alreadyWatching, got \(error)")
                return
            }
        }
    }
    
    func testNonExistentDirectoryThrowsError() {
        let missing = tempDir.url.appendingPathComponent("non_existent_subdir")
        XCTAssertThrowsError(
            try watcher.watchDownloads(
                in: missing,
                temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
                onUpdate: { _ in },
                onComplete: { },
                onError: { _ in }
            )
        ) { error in
            guard case FileWatcherError.directoryNotFound = error else {
                XCTFail("Expected directoryNotFound error, got \(error)")
                return
            }
        }
    }
    
    func testSafariDownloadPackageLifecycle() async throws {
        let completeExpectation = expectation(description: "Safari package complete")
        
        try watcher.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { _ in },
            onComplete: {
                completeExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        // Safari creates .download package folder
        _ = try tempDir.createDownloadPackage(named: "Installer.download", files: ["Info.plist": Data("plist".utf8)])
        try await Task.sleep(for: .milliseconds(300))
        
        // Safari finishes and moves package to final DMG
        try tempDir.removeFile(named: "Installer.download")
        try tempDir.createFile(named: "Installer.dmg", text: "dmg data")
        
        await fulfillment(of: [completeExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testWatchedDirectoryDeletedEmitsError() async throws {
        let subDir = try tempDir.createDirectory(named: "monitored_sub")
        let errorExpectation = expectation(description: "Error emitted on directory deletion")
        
        try watcher.watchDownloads(
            in: subDir,
            temporaryExtensions: DownloadPatternMatcher.defaultExtensions,
            onUpdate: { _ in },
            onComplete: { },
            onError: { error in
                guard case FileWatcherError.directoryNotFound = error else {
                    XCTFail("Expected directoryNotFound, got \(error)")
                    return
                }
                errorExpectation.fulfill()
            }
        )
        
        // Remove monitored subfolder
        try FileManager.default.removeItem(at: subDir)
        
        await fulfillment(of: [errorExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    // MARK: - Mock Service & Error Verification
    
    func testMockFileWatchingServiceLifecycleAndSimulations() throws {
        let mock = MockFileWatchingService()
        XCTAssertFalse(mock.isWatching)
        
        let receivedDownloadState = ThreadSafeBox<FileWatcherDownloadState?>(nil)
        let downloadCompleted = ThreadSafeBox<Bool>(false)
        let receivedError = ThreadSafeBox<Error?>(nil)
        
        try mock.watchDownloads(
            in: tempDir.url,
            temporaryExtensions: ["crdownload"],
            onUpdate: { receivedDownloadState.set($0) },
            onComplete: { downloadCompleted.set(true) },
            onError: { receivedError.set($0) }
        )
        
        XCTAssertTrue(mock.isWatching)
        XCTAssertEqual(mock.watchDownloadsCallCount, 1)
        XCTAssertEqual(mock.lastWatchedDirectory, tempDir.url)
        XCTAssertEqual(mock.lastTemporaryExtensions, ["crdownload"])
        
        // Simulate update
        let testState = FileWatcherDownloadState(directory: tempDir.url, activeDownloads: ["file.crdownload"])
        mock.simulateDownloadUpdate(testState)
        XCTAssertEqual(receivedDownloadState.get, testState)
        
        // Simulate complete
        mock.simulateDownloadComplete()
        XCTAssertTrue(downloadCompleted.get)
        
        // Simulate error
        let dummyError = FileWatcherError.unreadablePath(tempDir.url)
        mock.simulateError(dummyError)
        XCTAssertNotNil(receivedError.get)
        
        // Stop
        mock.stop()
        XCTAssertFalse(mock.isWatching)
        XCTAssertEqual(mock.stopCallCount, 1)
        
        // Test waitForFile mock simulation
        let receivedTargetState = ThreadSafeBox<FileWatcherTargetFileState?>(nil)
        let targetCompleted = ThreadSafeBox<Bool>(false)
        let targetFile = tempDir.url.appendingPathComponent("target.bin")
        
        try mock.waitForFile(
            at: targetFile,
            stabilizationDuration: 1.5,
            onUpdate: { receivedTargetState.set($0) },
            onComplete: { targetCompleted.set(true) },
            onError: { _ in }
        )
        
        XCTAssertTrue(mock.isWatching)
        XCTAssertEqual(mock.waitForFileCallCount, 1)
        XCTAssertEqual(mock.lastTargetPath, targetFile)
        XCTAssertEqual(mock.lastStabilizationDuration, 1.5)
        
        let targetState = FileWatcherTargetFileState(targetPath: targetFile, exists: true, isStabilizing: false, currentSize: 1024)
        mock.simulateTargetFileUpdate(targetState)
        XCTAssertEqual(receivedTargetState.get, targetState)
        
        mock.simulateTargetFileComplete()
        XCTAssertTrue(targetCompleted.get)
        
        // Reset
        mock.reset()
        XCTAssertFalse(mock.isWatching)
        XCTAssertEqual(mock.watchDownloadsCallCount, 0)
        XCTAssertEqual(mock.waitForFileCallCount, 0)
        XCTAssertEqual(mock.stopCallCount, 0)
        XCTAssertNil(mock.lastWatchedDirectory)
    }
    
    func testFileWatcherErrorDescriptions() {
        let dummyURL = URL(fileURLWithPath: "/tmp/nonexistent")
        let dirError = FileWatcherError.directoryNotFound(dummyURL)
        XCTAssertTrue(dirError.localizedDescription.contains("does not exist"))
        
        let unreadableError = FileWatcherError.unreadablePath(dummyURL)
        XCTAssertTrue(unreadableError.localizedDescription.contains("Cannot read"))
        
        let alreadyWatchingError = FileWatcherError.alreadyWatching
        XCTAssertTrue(alreadyWatchingError.localizedDescription.contains("already active"))
        
        let descriptorError = FileWatcherError.unableToOpenDescriptor(13)
        XCTAssertTrue(descriptorError.localizedDescription.contains("13"))
    }
}

