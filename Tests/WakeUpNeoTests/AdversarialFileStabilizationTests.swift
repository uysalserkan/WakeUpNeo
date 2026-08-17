import XCTest
import Darwin
@testable import WakeUpNeoCore

private final class AtomicBox<T>: @unchecked Sendable {
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

final class AdversarialFileStabilizationTests: XCTestCase {
    
    var tempDir: TestTempDirectory!
    var watcher: DefaultFileWatcherService!
    
    override func setUp() async throws {
        try await super.setUp()
        tempDir = try TestTempDirectory(prefix: "AdversarialStabilizationTests")
        watcher = DefaultFileWatcherService()
    }
    
    override func tearDown() async throws {
        watcher.stop()
        tempDir.cleanup()
        try await super.tearDown()
    }
    
    // MARK: - 1. Continuous Byte Append Streams
    
    func testContinuousByteAppendStreamPreventsPrematureStabilization() async throws {
        let targetURL = tempDir.url.appendingPathComponent("streaming_download.iso")
        let targetName = "streaming_download.iso"
        
        // Create initial 0-byte file
        try tempDir.createFile(named: targetName, contents: Data())
        
        let completedFlag = AtomicBox<Bool>(false)
        let observedSizes = AtomicBox<[Int64]>([])
        let completionExpectation = expectation(description: "Stream finishes and stabilizes")
        
        // Stabilization duration set to 0.5s
        try watcher.waitForFile(
            at: targetURL,
            stabilizationDuration: 0.5,
            onUpdate: { state in
                let current = observedSizes.get
                observedSizes.set(current + [state.currentSize])
            },
            onComplete: {
                completedFlag.set(true)
                completionExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error during stream: \(error)")
            }
        )
        
        XCTAssertTrue(watcher.isWatching)
        
        // Continuously append 100 bytes every 100ms for 1.2 seconds (12 appends total).
        // Since interval between writes (100ms) < stabilization duration (500ms),
        // the watcher must NEVER declare completion during this 1.2s append window.
        let appendCount = 12
        var totalBytesWritten: Int64 = 0
        
        for i in 1...appendCount {
            try await Task.sleep(for: .milliseconds(100))
            let chunk = Data(repeating: UInt8(i & 0xFF), count: 100)
            try tempDir.append(data: chunk, toFileNamed: targetName)
            totalBytesWritten += 100
            
            // Verify premature completion has not fired while writing is active
            XCTAssertFalse(
                completedFlag.get,
                "Premature completion fired at append #\(i) before stream ceased!"
            )
        }
        
        // Writing has now ceased. The watcher should now wait ~500ms and fire completion.
        await fulfillment(of: [completionExpectation], timeout: 3.0)
        
        XCTAssertTrue(completedFlag.get)
        XCTAssertFalse(watcher.isWatching)
        
        // Verify final file size on disk matches accumulated updates
        let finalMeta = FileStabilityChecker.readMetadata(at: targetURL)
        XCTAssertEqual(finalMeta.size, totalBytesWritten)
        XCTAssertEqual(totalBytesWritten, 1200)
    }
    
    func testHighFrequencyBurstWritesStabilizeCorrectly() async throws {
        let targetURL = tempDir.url.appendingPathComponent("burst.log")
        let targetName = "burst.log"
        try tempDir.createFile(named: targetName, text: "start\n")
        
        let completedExpectation = expectation(description: "Burst writes complete and stabilize")
        let finalStateBox = AtomicBox<FileWatcherTargetFileState?>(nil)
        
        try watcher.waitForFile(
            at: targetURL,
            stabilizationDuration: 0.4,
            onUpdate: { state in
                finalStateBox.set(state)
            },
            onComplete: {
                completedExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        // Perform 50 rapid fire appends in tight loop without sleeps
        for i in 1...50 {
            try tempDir.append(data: Data("burst line \(i)\n".utf8), toFileNamed: targetName)
        }
        
        await fulfillment(of: [completedExpectation], timeout: 3.0)
        
        let diskMeta = FileStabilityChecker.readMetadata(at: targetURL)
        XCTAssertGreaterThan(diskMeta.size, 500)
        if let lastState = finalStateBox.get {
            XCTAssertEqual(lastState.currentSize, diskMeta.size)
            XCTAssertFalse(lastState.isStabilizing)
        }
    }
    
    // MARK: - 2. Fast-Path Already-Settled Files
    
    func testFastPathPreExistingFileCompletesImmediately() async throws {
        let file = try tempDir.createFile(named: "settled_video.mp4", text: "completed video content")
        // Set modification time 60 seconds in the past
        let pastDate = Date.now.addingTimeInterval(-60)
        try FileManager.default.setAttributes(
            [.modificationDate: pastDate],
            ofItemAtPath: file.path(percentEncoded: false)
        )
        
        let startTime = ContinuousClock.now
        let completedExpectation = expectation(description: "Fast-path triggers completion immediately")
        
        try watcher.waitForFile(
            at: file,
            stabilizationDuration: 2.0, // 2.0s stabilization requested
            onUpdate: { _ in },
            onComplete: {
                completedExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        // Fast-path should fire in well under 200ms, not wait for 2.0s
        await fulfillment(of: [completedExpectation], timeout: 0.5)
        let elapsedTime = ContinuousClock.now - startTime
        
        XCTAssertLessThan(elapsedTime, .milliseconds(400), "Fast-path must not wait for 2.0s stabilization window")
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testFastPathPreExistingZeroByteFile() async throws {
        let file = try tempDir.createFile(named: "touch.marker", contents: Data())
        let pastDate = Date.now.addingTimeInterval(-30)
        try FileManager.default.setAttributes(
            [.modificationDate: pastDate],
            ofItemAtPath: file.path(percentEncoded: false)
        )
        
        let completedExpectation = expectation(description: "Zero byte pre-existing file completes via fast-path")
        
        try watcher.waitForFile(
            at: file,
            stabilizationDuration: 1.0,
            onUpdate: { _ in },
            onComplete: {
                completedExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        await fulfillment(of: [completedExpectation], timeout: 0.5)
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testFastPathPreExistingDirectoryPackage() async throws {
        let package = try tempDir.createDownloadPackage(
            named: "Application.app",
            files: [
                "Info.plist": Data("<plist></plist>".utf8),
                "app": Data([0xCA, 0xFE, 0xBA, 0xBE]),
                "icon.icns": Data(repeating: 0x01, count: 512)
            ]
        )
        
        let pastDate = Date.now.addingTimeInterval(-120)
        // Mark all files in package with past date
        let enumerator = FileManager.default.enumerator(at: package, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            try? FileManager.default.setAttributes([.modificationDate: pastDate], ofItemAtPath: item.path(percentEncoded: false))
        }
        try FileManager.default.setAttributes([.modificationDate: pastDate], ofItemAtPath: package.path(percentEncoded: false))
        
        let completedExpectation = expectation(description: "Directory package completes via fast-path")
        
        try watcher.waitForFile(
            at: package,
            stabilizationDuration: 1.5,
            onUpdate: { _ in },
            onComplete: {
                completedExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        await fulfillment(of: [completedExpectation], timeout: 0.5)
        XCTAssertFalse(watcher.isWatching)
    }
    
    // MARK: - 3. Directory Packages (.app, .bundle, nested targets)
    
    func testDirectoryPackageNestedFilesStreamStabilization() async throws {
        let package = try tempDir.createDirectory(named: "Payload.bundle")
        let completedFlag = AtomicBox<Bool>(false)
        let completedExpectation = expectation(description: "Nested bundle finishes and stabilizes")
        
        try watcher.waitForFile(
            at: package,
            stabilizationDuration: 0.5,
            onUpdate: { _ in },
            onComplete: {
                completedFlag.set(true)
                completedExpectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )
        
        // Progressively add nested subfolders and files every 100ms
        let subDir = package.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        for i in 1...6 {
            try await Task.sleep(for: .milliseconds(100))
            let chunkFile = subDir.appendingPathComponent("chunk_\(i).dat")
            try Data(repeating: UInt8(i), count: 200).write(to: chunkFile)
            XCTAssertFalse(completedFlag.get, "Package stabilized prematurely while files were being added")
        }
        
        await fulfillment(of: [completedExpectation], timeout: 3.0)
        XCTAssertTrue(completedFlag.get)
        
        let meta = FileStabilityChecker.readMetadata(at: package)
        XCTAssertEqual(meta.size, 1200)
    }
    
    func testDirectoryPackageSubfileDeletionResetsStabilization() throws {
        let package = try tempDir.createDownloadPackage(
            named: "Draft.download",
            files: [
                "partA": Data("12345".utf8),
                "partB": Data("67890".utf8)
            ]
        )
        
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        let state0 = checker.evaluate(at: package, now: t0)
        XCTAssertTrue(state0.isStabilizing)
        XCTAssertEqual(state0.currentSize, 10)
        
        // At t0 + 0.5s, delete partB
        let partB = package.appendingPathComponent("partB")
        try FileManager.default.removeItem(at: partB)
        
        let stateDelete = checker.evaluate(at: package, now: t0.addingTimeInterval(0.5))
        XCTAssertTrue(stateDelete.isStabilizing)
        XCTAssertEqual(stateDelete.currentSize, 5)
        
        // At t0 + 1.1s (only 0.6s after deletion), should still be stabilizing
        let stateInter = checker.evaluate(at: package, now: t0.addingTimeInterval(1.1))
        XCTAssertTrue(stateInter.isStabilizing)
        
        // At t0 + 1.6s (1.1s after deletion), should settle
        let stateSettled = checker.evaluate(at: package, now: t0.addingTimeInterval(1.6))
        XCTAssertFalse(stateSettled.isStabilizing)
        XCTAssertEqual(stateSettled.currentSize, 5)
    }
    
    func testEmptyDirectoryTargetStabilization() async throws {
        let emptyDir = try tempDir.createDirectory(named: "EmptyTargetDir")
        let completeExpectation = expectation(description: "Empty directory stabilizes")
        
        try watcher.waitForFile(
            at: emptyDir,
            stabilizationDuration: 0.3,
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
    
    // MARK: - 4. Deleted Parent Directories & Missing Target
    
    func testDeletedParentDirectoryDuringWaitForFileEmitsError() async throws {
        let subDir = try tempDir.createDirectory(named: "watched_parent")
        let targetFile = subDir.appendingPathComponent("incoming_artifact.dmg")
        
        let errorExpectation = expectation(description: "Error emitted when parent dir deleted")
        
        try watcher.waitForFile(
            at: targetFile,
            stabilizationDuration: 1.0,
            onUpdate: { _ in },
            onComplete: {
                XCTFail("Completion should not fire on deleted parent directory")
            },
            onError: { error in
                guard case FileWatcherError.directoryNotFound(let dir) = error else {
                    XCTFail("Expected directoryNotFound, got \(error)")
                    return
                }
                XCTAssertEqual(dir.path(percentEncoded: false), subDir.path(percentEncoded: false))
                errorExpectation.fulfill()
            }
        )
        
        XCTAssertTrue(watcher.isWatching)
        
        // Delete the parent directory
        try FileManager.default.removeItem(at: subDir)
        
        await fulfillment(of: [errorExpectation], timeout: 3.0)
        XCTAssertFalse(watcher.isWatching)
    }
    
    func testNonExistentParentDirectoryThrowsOnStart() {
        let invalidParent = tempDir.url.appendingPathComponent("does_not_exist_xyz").appendingPathComponent("file.zip")
        
        XCTAssertThrowsError(
            try watcher.waitForFile(
                at: invalidParent,
                stabilizationDuration: 1.0,
                onUpdate: { _ in },
                onComplete: { },
                onError: { _ in }
            )
        ) { error in
            guard case FileWatcherError.directoryNotFound = error else {
                XCTFail("Expected FileWatcherError.directoryNotFound, got \(error)")
                return
            }
        }
    }
    
    // MARK: - 5. Clock Monotonicity & Time Shifts
    
    func testFutureModificationDateDoesNotBypassStabilization() throws {
        let file = try tempDir.createFile(named: "future_timestamp.dat", text: "future clock skew")
        // Set modification time 100 seconds into the future
        let futureDate = Date.now.addingTimeInterval(100)
        try FileManager.default.setAttributes(
            [.modificationDate: futureDate],
            ofItemAtPath: file.path(percentEncoded: false)
        )
        
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        // First observation: timeSinceLastModification = t0 - futureDate is negative (< 1.0)
        // Must NOT trigger fast-path!
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.exists)
        XCTAssertTrue(state0.isStabilizing, "Future-dated file must stabilize normally, not fast-path")
        
        // At t0 + 0.5s: still stabilizing
        let state1 = checker.evaluate(at: file, now: t0.addingTimeInterval(0.5))
        XCTAssertTrue(state1.isStabilizing)
        
        // At t0 + 1.1s: locally stable
        let state2 = checker.evaluate(at: file, now: t0.addingTimeInterval(1.1))
        XCTAssertFalse(state2.isStabilizing, "File should settle after local observation window")
    }
    
    func testBackwardTimeJumpPreventsPrematureCompletion() throws {
        let file = try tempDir.createFile(named: "ntp_jump.txt", text: "test")
        let checker = FileStabilityChecker(stabilizationDuration: 2.0)
        let t0 = Date.now
        
        // Observation 1 at t0
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.isStabilizing)
        
        // NTP jumps wall clock 10 seconds backwards
        let tJumpBack = t0.addingTimeInterval(-10)
        let stateBack = checker.evaluate(at: file, now: tJumpBack)
        XCTAssertTrue(stateBack.isStabilizing, "Backward clock step must not complete stabilization")
        
        // At t0 + 2.1s (forward in time by 2.1s from t0)
        let stateNormal = checker.evaluate(at: file, now: t0.addingTimeInterval(2.1))
        XCTAssertFalse(stateNormal.isStabilizing)
    }
    
    // MARK: - 6. Target File Life Cycle (Disappearing & Truncation)
    
    func testTargetFileCreatedThenDeletedThenRecreated() throws {
        let file = try tempDir.createFile(named: "ephemeral.tmp", text: "v1")
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.exists)
        XCTAssertTrue(state0.isStabilizing)
        
        // File deleted before stabilizing
        try tempDir.removeFile(named: "ephemeral.tmp")
        let stateDeleted = checker.evaluate(at: file, now: t0.addingTimeInterval(0.5))
        XCTAssertFalse(stateDeleted.exists)
        XCTAssertFalse(stateDeleted.isStabilizing)
        
        // File recreated with different content at t0 + 0.8s
        try tempDir.createFile(named: "ephemeral.tmp", text: "v2-recreated-longer-payload")
        let stateRecreated = checker.evaluate(at: file, now: t0.addingTimeInterval(0.8))
        XCTAssertTrue(stateRecreated.exists)
        XCTAssertTrue(stateRecreated.isStabilizing)
        XCTAssertEqual(stateRecreated.currentSize, 27)
        
        // At t0 + 1.5s (only 0.7s after recreation), still stabilizing
        let stateMid = checker.evaluate(at: file, now: t0.addingTimeInterval(1.5))
        XCTAssertTrue(stateMid.isStabilizing)
        
        // At t0 + 1.9s (1.1s after recreation), stable
        let stateFinal = checker.evaluate(at: file, now: t0.addingTimeInterval(1.9))
        XCTAssertFalse(stateFinal.isStabilizing)
        XCTAssertEqual(stateFinal.currentSize, 27)
    }
    
    func testTargetFileTruncationResetsStabilization() throws {
        let file = try tempDir.createFile(named: "shrink.log", text: "initial long content that will be truncated")
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.isStabilizing)
        XCTAssertEqual(state0.currentSize, 43)
        
        // Truncate file to 5 bytes
        try Data("short".utf8).write(to: file)
        // Ensure filesystem mod date is bumped
        try FileManager.default.setAttributes([.modificationDate: t0.addingTimeInterval(0.5)], ofItemAtPath: file.path(percentEncoded: false))
        
        let stateShrunk = checker.evaluate(at: file, now: t0.addingTimeInterval(0.5))
        XCTAssertTrue(stateShrunk.isStabilizing)
        XCTAssertEqual(stateShrunk.currentSize, 5)
        
        let stateSettled = checker.evaluate(at: file, now: t0.addingTimeInterval(1.6))
        XCTAssertFalse(stateSettled.isStabilizing)
        XCTAssertEqual(stateSettled.currentSize, 5)
    }
    
    // MARK: - 7. Multithreaded Concurrency & Race Conditions
    
    func testConcurrentEvaluationsUnderContention() throws {
        let file = try tempDir.createFile(named: "contention.bin", text: "thread-safety-test")
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        
        let iterations = 200
        let group = DispatchGroup()
        let failureCount = AtomicBox<Int>(0)
        
        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let now = Date.now.addingTimeInterval(Double(i) * 0.01)
                let state = checker.evaluate(at: file, now: now)
                if !state.exists {
                    failureCount.set(failureCount.get + 1)
                }
                if i % 50 == 0 {
                    checker.reset()
                }
                group.leave()
            }
        }
        
        let waitResult = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(waitResult, .success, "Concurrent evaluation timed out")
        XCTAssertEqual(failureCount.get, 0, "Concurrent evaluation reported non-existent file on existing path")
    }
    
    // MARK: - 8. Resource & File Descriptor Leak Prevention
    
    func testRapidStartStopCyclesDoNotLeakDescriptors() throws {
        // Run 25 rapid start and stop cycles
        for _ in 1...25 {
            let freshWatcher = DefaultFileWatcherService()
            try freshWatcher.watchDownloads(
                in: tempDir.url,
                temporaryExtensions: ["crdownload"],
                onUpdate: { _ in },
                onComplete: { },
                onError: { _ in }
            )
            XCTAssertTrue(freshWatcher.isWatching)
            freshWatcher.stop()
            XCTAssertFalse(freshWatcher.isWatching)
        }
    }
}
