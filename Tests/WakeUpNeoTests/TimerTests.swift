import XCTest
@testable import WakeUpNeoCore

// MARK: - TimerTests
//
// Verifies countdown accuracy, no-countdown in indefinite mode,
// reset on stop, correct end-date computation, and past-date expiry.

@MainActor
final class TimerTests: XCTestCase {

    var manager: SleepManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let systemMock  = MockSleepService()
        let displayMock = MockSleepService()
        let composite   = CompositeSleepService(
            systemSleepService:  systemMock,
            displaySleepService: displayMock
        )
        manager = SleepManager(compositeService: composite)
    }

    override func tearDownWithError() throws {
        manager?.stop()
        try super.tearDownWithError()
    }

    // MARK: - Countdown accuracy

    /// The countdown must stay within +-1 second of wall-clock time
    /// after one tick of the countdown loop.
    func testCountdownAccuracyAfterOneTick() async throws {
        let duration: TimeInterval = 10
        let startDate = Date.now

        manager.start(for: duration)

        // Wait for the countdown task to produce its first update
        try await Task.sleep(for: .milliseconds(1_200))

        let elapsed          = Date.now.timeIntervalSince(startDate)
        let expectedRemaining = duration - elapsed
        let actualRemaining   = manager.remainingTime

        XCTAssertEqual(
            actualRemaining,
            expectedRemaining,
            accuracy: 1.0,
            "Countdown should match wall clock within +-1 second"
        )
    }

    // MARK: - No countdown in indefinite mode

    func testIndefiniteModeHasNoCountdown() {
        manager.startIndefinitely()
        XCTAssertEqual(manager.remainingTime, 0, "Indefinite sessions should not show a countdown")
    }

    // MARK: - Countdown resets on stop

    func testCountdownResetsOnStop() throws {
        manager.start(for: 60)
        manager.stop()
        XCTAssertEqual(manager.remainingTime, 0, "remainingTime must be 0 after stop()")
    }

    // MARK: - Correct end date for timed sessions

    func testTimedModeEndDateIsCorrect() {
        let duration: TimeInterval = 3600
        let before = Date.now

        manager.start(for: duration)

        let after = Date.now
        guard case .timed(let endDate) = manager.mode else {
            XCTFail("Expected .timed mode")
            return
        }

        let expectedMin = before.addingTimeInterval(duration)
        let expectedMax = after.addingTimeInterval(duration)
        XCTAssertGreaterThanOrEqual(endDate.timeIntervalSince1970, expectedMin.timeIntervalSince1970 - 1)
        XCTAssertLessThanOrEqual(endDate.timeIntervalSince1970,    expectedMax.timeIntervalSince1970 + 1)
    }

    // MARK: - Already-expired date expires immediately

    func testPastEndDateExpiresImmediately() async throws {
        // A date in the past means remaining < 0 on the first countdown tick.
        let pastDate = Date.now.addingTimeInterval(-1)
        manager.start(until: pastDate)

        XCTAssertTrue(manager.isActive, "Session starts active")

        // The countdown task detects expiry on its first iteration
        try await Task.sleep(for: .seconds(2))

        XCTAssertFalse(manager.isActive, "Session with past end date should auto-expire quickly")
    }

    // MARK: - Countdown does not run when inactive

    func testCountdownIsZeroWhenInactive() {
        XCTAssertEqual(manager.remainingTime, 0, "remainingTime should be 0 when no session is running")
    }
}
