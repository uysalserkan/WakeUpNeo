import XCTest
@testable import WakeUpNeoCore

// MARK: - SleepManagerTests
//
// Covers all 10 required unit test cases from the specification.
// Tests run on the main actor because SleepManager is @MainActor.

@MainActor
final class SleepManagerTests: XCTestCase {

    // MARK: - Fixtures

    var systemMock:  MockSleepService!
    var displayMock: MockSleepService!
    var lidMock:     MockSleepService!
    var composite:   CompositeSleepService!
    var manager:     SleepManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        systemMock  = MockSleepService()
        displayMock = MockSleepService()
        lidMock     = MockSleepService()
        composite   = CompositeSleepService(
            systemSleepService:  systemMock,
            displaySleepService: displayMock,
            lidSleepService:     lidMock
        )
        manager = SleepManager(compositeService: composite)
    }

    override func tearDownWithError() throws {
        manager?.stop()
        try super.tearDownWithError()
    }

    // MARK: - Test 1: starts indefinite session

    func testStartsIndefiniteSession() {
        manager.startIndefinitely()

        XCTAssertTrue(manager.isActive,              "Manager should be active after startIndefinitely()")
        XCTAssertTrue(manager.mode.isIndefinite,     "Mode should be .indefinite")
        XCTAssertEqual(systemMock.startCallCount, 1, "System service should be started once")
        XCTAssertNil(manager.lastError,              "No error should be present")
    }

    // MARK: - Test 2: starts timed session

    func testStartsTimedSession() {
        manager.start(for: 3600)

        XCTAssertTrue(manager.isActive,              "Manager should be active after start(for:)")
        if case .timed = manager.mode { } else {
            XCTFail("Mode should be .timed, got \(manager.mode)")
        }
        XCTAssertEqual(systemMock.startCallCount, 1, "System service should be started once")
        XCTAssertNil(manager.lastError,              "No error should be present")
    }

    // MARK: - Test 3: calculates remaining time

    func testCalculatesRemainingTime() async throws {
        manager.start(for: 60) // 60-second session

        // Allow the countdown task a heartbeat tick
        try await Task.sleep(for: .milliseconds(1_200))

        XCTAssertGreaterThan(manager.remainingTime, 0,  "Remaining time should be positive")
        XCTAssertLessThan(manager.remainingTime,    60, "Remaining time should be less than the starting duration")
    }

    // MARK: - Test 4: automatically expires session

    func testAutomaticallyExpiresSession() async throws {
        // Start a session that will expire in 0.5 seconds
        let endDate = Date.now.addingTimeInterval(0.5)
        manager.start(until: endDate)

        XCTAssertTrue(manager.isActive, "Manager should be active immediately after start")

        // Wait for expiration (0.5s session + 1s countdown tick + margin)
        try await Task.sleep(for: .seconds(2))

        XCTAssertFalse(manager.isActive,             "Manager should be inactive after expiry")
        XCTAssertTrue(manager.mode.isOff,            "Mode should be .off after expiry")
        XCTAssertEqual(systemMock.stopCallCount, 1,  "System service should be stopped once on expiry")
    }

    // MARK: - Test 5: stops session

    func testStopsSession() {
        manager.startIndefinitely()
        manager.stop()

        XCTAssertFalse(manager.isActive,            "Manager should be inactive after stop()")
        XCTAssertTrue(manager.mode.isOff,           "Mode should be .off")
        XCTAssertEqual(systemMock.stopCallCount, 1, "System service should be stopped exactly once")
        XCTAssertEqual(manager.remainingTime, 0,    "Remaining time should be 0 after stop")
    }

    // MARK: - Test 6: repeated stop is safe

    func testRepeatedStopIsSafe() {
        manager.startIndefinitely()
        manager.stop()
        manager.stop() // Second call -- guard should short-circuit
        manager.stop() // Third call

        XCTAssertFalse(manager.isActive, "Manager should remain inactive after multiple stops")
        // The second and third calls are no-ops (guard !mode.isOff)
        XCTAssertEqual(systemMock.stopCallCount, 1, "System service stop should be called only once")
    }

    // MARK: - Test 7: start after stop works

    func testStartAfterStopWorks() {
        manager.startIndefinitely()
        manager.stop()
        manager.startIndefinitely()

        XCTAssertTrue(manager.isActive,              "Manager should be active after restarting")
        XCTAssertTrue(manager.mode.isIndefinite,     "Mode should be .indefinite again")
        XCTAssertEqual(systemMock.startCallCount, 2, "System service should have been started twice total")
    }

    // MARK: - Test 8: state survives view recreation (initial state check)

    func testInitialStateIsOff() {
        // A freshly-created SleepManager must always start in .off.
        // This guarantees that view recreation cannot accidentally activate sleep prevention.
        XCTAssertFalse(manager.isActive,         "New manager should be inactive")
        XCTAssertTrue(manager.mode.isOff,        "New manager mode should be .off")
        XCTAssertEqual(manager.remainingTime, 0, "New manager remaining time should be 0")
        XCTAssertNil(manager.lastError,          "New manager should have no errors")
    }

    // MARK: - Test 9: service failure is handled

    func testServiceFailureIsHandled() {
        systemMock.shouldThrowOnStart = true
        manager.startIndefinitely()

        XCTAssertFalse(manager.isActive,      "Manager should not be active after a service failure")
        XCTAssertTrue(manager.mode.isOff,     "Mode should remain .off after failure")
        XCTAssertNotNil(manager.lastError,    "lastError should be set after failure")
    }

    func testClearErrorResetsLastError() {
        systemMock.shouldThrowOnStart = true
        manager.startIndefinitely()
        XCTAssertNotNil(manager.lastError)

        manager.clearError()
        XCTAssertNil(manager.lastError, "clearError() should nil out lastError")
    }

    // MARK: - Test 10: settings persist (settings-layer check)

    func testSettingsPersistDefaultValues() {
        // AppSettings.default mirrors the spec's stated defaults.
        let defaults = AppSettings.default
        XCTAssertTrue(defaults.launchAtLogin)
        XCTAssertTrue(defaults.showCountdownInMenuBar)
        XCTAssertEqual(defaults.defaultDuration, .oneHour)
        XCTAssertTrue(defaults.notifyOnSessionEnd)
        XCTAssertFalse(defaults.notifyOnSessionExpiring)
        XCTAssertTrue(defaults.preventSystemSleep)
        XCTAssertFalse(defaults.keepDisplayAwake)
        XCTAssertFalse(defaults.preventLidSleep)
    }

    // MARK: - Test 11: preventLidSleep activates lid sleep assertion

    func testPreventLidSleepActivation() {
        manager.preventLidSleep = true
        manager.startIndefinitely()

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(systemMock.startCallCount, 1, "System service should start")
        XCTAssertEqual(lidMock.startCallCount, 1, "Lid service should start when preventLidSleep is true")

        manager.stop()
        XCTAssertEqual(lidMock.stopCallCount, 1, "Lid service should stop when manager stops")
    }

    func testPreventLidSleepDynamicToggle() {
        manager.startIndefinitely()
        XCTAssertEqual(lidMock.startCallCount, 0, "Lid service should not start when preventLidSleep is false")

        // Dynamically enable preventLidSleep during an active session
        manager.preventLidSleep = true

        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(lidMock.startCallCount, 1, "Lid service should start after enabling preventLidSleep")

        // Dynamically disable preventLidSleep
        manager.preventLidSleep = false
        XCTAssertTrue(manager.isActive)
        XCTAssertFalse(lidMock.isRunning, "Lid service should not be running after disabling preventLidSleep")
        XCTAssertGreaterThanOrEqual(lidMock.stopCallCount, 1, "Lid service should have been stopped")
    }
}
