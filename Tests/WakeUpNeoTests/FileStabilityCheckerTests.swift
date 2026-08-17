import XCTest
@testable import WakeUpNeoCore

final class FileStabilityCheckerTests: XCTestCase {
    
    var tempDir: TestTempDirectory!
    
    override func setUp() async throws {
        try await super.setUp()
        tempDir = try TestTempDirectory(prefix: "FileStabilityCheckerTests")
    }
    
    override func tearDown() async throws {
        tempDir.cleanup()
        try await super.tearDown()
    }
    
    // MARK: - Tier 1: Core Stability Evaluation
    
    func testNonExistentFileReportsFalse() {
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let nonExistent = tempDir.url.appendingPathComponent("missing.txt")
        let state = checker.evaluate(at: nonExistent)
        
        XCTAssertFalse(state.exists)
        XCTAssertFalse(state.isStabilizing)
        XCTAssertEqual(state.currentSize, 0)
    }
    
    func testFastPathStableForOlderFile() throws {
        let file = try tempDir.createFile(named: "old_artifact.bin", text: "stable data")
        // Set modification date 10 seconds in the past
        let pastDate = Date.now.addingTimeInterval(-10)
        try FileManager.default.setAttributes([.modificationDate: pastDate], ofItemAtPath: file.path(percentEncoded: false))
        
        let checker = FileStabilityChecker(stabilizationDuration: 2.0)
        let state = checker.evaluate(at: file)
        
        XCTAssertTrue(state.exists)
        XCTAssertFalse(state.isStabilizing, "Pre-existing file modified in past should immediately be stable")
        XCTAssertEqual(state.currentSize, 11)
    }
    
    func testNewlyCreatedFileBeginsStabilizingAndSettles() throws {
        let file = try tempDir.createFile(named: "new_render.mov", text: "rendering...")
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        // Initial evaluation
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.exists)
        XCTAssertTrue(state0.isStabilizing)
        
        // After 0.5s (less than 1.0s)
        let state1 = checker.evaluate(at: file, now: t0.addingTimeInterval(0.5))
        XCTAssertTrue(state1.exists)
        XCTAssertTrue(state1.isStabilizing)
        
        // After 1.1s (greater than 1.0s without changes)
        let state2 = checker.evaluate(at: file, now: t0.addingTimeInterval(1.1))
        XCTAssertTrue(state2.exists)
        XCTAssertFalse(state2.isStabilizing, "File should settle after stabilizationDuration")
        XCTAssertEqual(state2.currentSize, 12)
    }
    
    func testFileGrowthResetsStabilizationTimer() throws {
        let file = try tempDir.createFile(named: "stream.log", text: "part1")
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        _ = checker.evaluate(at: file, now: t0)
        
        // At t0 + 0.8s, file grows
        try tempDir.append(data: Data("part2".utf8), toFileNamed: "stream.log")
        let stateGrow = checker.evaluate(at: file, now: t0.addingTimeInterval(0.8))
        XCTAssertTrue(stateGrow.isStabilizing)
        XCTAssertEqual(stateGrow.currentSize, 10)
        
        // At t0 + 1.2s (only 0.4s after growth), should still be stabilizing
        let stateIntermediate = checker.evaluate(at: file, now: t0.addingTimeInterval(1.2))
        XCTAssertTrue(stateIntermediate.isStabilizing)
        
        // At t0 + 1.9s (1.1s after last growth), should be stable
        let stateSettled = checker.evaluate(at: file, now: t0.addingTimeInterval(1.9))
        XCTAssertFalse(stateSettled.isStabilizing)
        XCTAssertEqual(stateSettled.currentSize, 10)
    }
    
    // MARK: - Tier 2: Boundary Cases
    
    func testZeroByteFileStabilization() throws {
        let file = try tempDir.createFile(named: "touch.txt", contents: Data())
        let checker = FileStabilityChecker(stabilizationDuration: 0.5)
        let t0 = Date.now
        
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.exists)
        XCTAssertTrue(state0.isStabilizing)
        XCTAssertEqual(state0.currentSize, 0)
        
        let stateSettled = checker.evaluate(at: file, now: t0.addingTimeInterval(0.6))
        XCTAssertTrue(stateSettled.exists)
        XCTAssertFalse(stateSettled.isStabilizing)
        XCTAssertEqual(stateSettled.currentSize, 0)
    }
    
    func testFileDeletedDuringStabilization() throws {
        let file = try tempDir.createFile(named: "temp_work.tmp", text: "working")
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.exists)
        XCTAssertTrue(state0.isStabilizing)
        
        try tempDir.removeFile(named: "temp_work.tmp")
        
        let stateDeleted = checker.evaluate(at: file, now: t0.addingTimeInterval(0.5))
        XCTAssertFalse(stateDeleted.exists)
        XCTAssertFalse(stateDeleted.isStabilizing)
        XCTAssertEqual(stateDeleted.currentSize, 0)
    }
    
    func testDirectoryPackageStabilization() throws {
        let package = try tempDir.createDownloadPackage(
            named: "AppBundle.download",
            files: ["info": Data("info".utf8), "payload": Data([0x01, 0x02, 0x03])]
        )
        let checker = FileStabilityChecker(stabilizationDuration: 1.0)
        let t0 = Date.now
        
        let state0 = checker.evaluate(at: package, now: t0)
        XCTAssertTrue(state0.exists)
        XCTAssertTrue(state0.isStabilizing)
        XCTAssertEqual(state0.currentSize, 7)
        
        let stateSettled = checker.evaluate(at: package, now: t0.addingTimeInterval(1.1))
        XCTAssertTrue(stateSettled.exists)
        XCTAssertFalse(stateSettled.isStabilizing)
    }
    
    func testResetClearsState() throws {
        let file = try tempDir.createFile(named: "reset_test.dat", text: "data")
        let checker = FileStabilityChecker(stabilizationDuration: 2.0)
        let t0 = Date.now
        
        let state0 = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(state0.isStabilizing)
        
        checker.reset()
        
        // After reset, evaluated at same timestamp acts as new observation
        let stateAfterReset = checker.evaluate(at: file, now: t0)
        XCTAssertTrue(stateAfterReset.isStabilizing)
    }
}
