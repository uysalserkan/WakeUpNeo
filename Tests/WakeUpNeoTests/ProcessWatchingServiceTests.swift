import XCTest
import Foundation
@testable import WakeUpNeoCore

final class ProcessWatchingServiceTests: XCTestCase {

    private var service: DefaultProcessWatchingService!

    override func setUp() {
        super.setUp()
        service = DefaultProcessWatchingService()
    }

    override func tearDown() {
        service.stop()
        service = nil
        super.tearDown()
    }

    // MARK: - 1. Running Applications & Liveness

    func testRunningApplicationsDiscovery() {
        let apps = service.runningApplications()
        XCTAssertFalse(apps.isEmpty, "Running applications list should not be empty on macOS")

        for app in apps {
            XCTAssertGreaterThan(app.pid, 0)
            XCTAssertFalse(app.name.isEmpty)
        }
    }

    func testIsProcessAlive() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(service.isProcessAlive(pid: myPID), "Current test process must be alive")

        XCTAssertFalse(service.isProcessAlive(pid: -1), "Negative PID must be reported as dead")
        XCTAssertFalse(service.isProcessAlive(pid: 0), "PID 0 must be reported as dead")
        XCTAssertFalse(service.isProcessAlive(pid: 999_999), "Non-existent PID 999999 must be reported as dead")
    }

    // MARK: - 2. Error Cases

    func testWatchProcessNonExistentPIDThrows() {
        let deadPID: Int32 = 999_999
        XCTAssertThrowsError(
            try service.watchProcess(
                pid: deadPID,
                name: "GhostProcess",
                onTerminate: {},
                onError: { _ in }
            )
        ) { error in
            guard case ProcessWatcherError.processNotFound(let pid) = error else {
                XCTFail("Expected processNotFound error, got \(error)")
                return
            }
            XCTAssertEqual(pid, deadPID)
        }
    }

    func testWatchProcessDoubleWatchThrowsAlreadyWatching() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        XCTAssertNoThrow(
            try service.watchProcess(
                pid: myPID,
                name: "TestRunner",
                onTerminate: {},
                onError: { _ in }
            )
        )
        XCTAssertTrue(service.isWatching)

        XCTAssertThrowsError(
            try service.watchProcess(
                pid: myPID,
                name: "TestRunnerAgain",
                onTerminate: {},
                onError: { _ in }
            )
        ) { error in
            guard case ProcessWatcherError.alreadyWatching = error else {
                XCTFail("Expected alreadyWatching error, got \(error)")
                return
            }
        }
    }

    // MARK: - 3. Process Termination Detection

    func testWatchProcessTerminationDetectionWithSubprocess() async throws {
        // Spawn a child process that sleeps for 0.4 seconds
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.4"]
        try process.run()

        let childPID = process.processIdentifier
        XCTAssertGreaterThan(childPID, 0)

        let expectation = XCTestExpectation(description: "Subprocess termination detected")

        try service.watchProcess(
            pid: childPID,
            name: "sleep",
            onTerminate: {
                expectation.fulfill()
            },
            onError: { error in
                XCTFail("Unexpected error: \(error)")
            }
        )

        XCTAssertTrue(service.isWatching)

        await fulfillment(of: [expectation], timeout: 3.0)
        XCTAssertFalse(service.isWatching)
    }

    // MARK: - 4. SleepManager Integration

    @MainActor
    func testSleepManagerProcessWatchingSessionManualStop() {
        let mockSleepService = MockSleepService()
        let composite = CompositeSleepService(
            systemSleepService: mockSleepService,
            displaySleepService: mockSleepService,
            lidSleepService: mockSleepService
        )
        let manager = SleepManager(compositeService: composite)

        let myPID = ProcessInfo.processInfo.processIdentifier
        manager.startWatchingProcess(pid: myPID, name: "TestRunner", bundleIdentifier: "com.apple.dt.xctest")

        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isWatchingProcess)
        XCTAssertTrue(manager.mode.isSmartWatching)
        XCTAssertEqual(manager.mode.watchedPID, myPID)
        XCTAssertEqual(manager.mode.watchedProcessName, "TestRunner")
        XCTAssertEqual(manager.mode.watchedBundleIdentifier, "com.apple.dt.xctest")
        XCTAssertTrue(mockSleepService.isRunning)

        manager.stop()
        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(mockSleepService.isRunning)
    }

    @MainActor
    func testSleepManagerAutoStopOnProcessTermination() async throws {
        let mockSleepService = MockSleepService()
        let composite = CompositeSleepService(
            systemSleepService: mockSleepService,
            displaySleepService: mockSleepService,
            lidSleepService: mockSleepService
        )
        let manager = SleepManager(compositeService: composite)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.4"]
        try process.run()

        let childPID = process.processIdentifier

        let terminationNotification = XCTestExpectation(description: "wakeUpNeoProcessTerminated posted")
        let token = NotificationCenter.default.addObserver(
            forName: .wakeUpNeoProcessTerminated,
            object: nil,
            queue: .main
        ) { notification in
            if let info = notification.object as? MonitoredProcessInfo, info.pid == childPID {
                terminationNotification.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        manager.startWatchingProcess(pid: childPID, name: "sleep")
        XCTAssertTrue(manager.isActive)
        XCTAssertTrue(manager.mode.isWatchingProcess)

        await fulfillment(of: [terminationNotification], timeout: 3.0)

        // Give MainActor a moment to process the handler
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(manager.isActive)
        XCTAssertTrue(manager.mode.isOff)
        XCTAssertFalse(mockSleepService.isRunning)
    }
}
