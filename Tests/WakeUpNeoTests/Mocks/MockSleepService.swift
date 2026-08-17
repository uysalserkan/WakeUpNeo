import Foundation
@testable import WakeUpNeoCore

// MARK: - MockSleepService

/// A test double for `SleepPreventionService`.
///
/// Tracks call counts and supports injecting deliberate failures,
/// enabling deterministic unit tests without touching IOKit or ProcessInfo.
public final class MockSleepService: SleepPreventionService, @unchecked Sendable {

    // MARK: - Call tracking
    public private(set) var startCallCount = 0
    public private(set) var stopCallCount  = 0
    public private(set) var isRunning      = false

    // MARK: - Failure injection
    /// Set to `true` to make `start()` throw `MockError.intentionalFailure`.
    public var shouldThrowOnStart = false

    public enum MockError: Error, LocalizedError {
        case intentionalFailure
        public var errorDescription: String? {
            "Mock: intentional failure for testing"
        }
    }

    public init() {}

    public func start() throws {
        startCallCount += 1
        if shouldThrowOnStart { throw MockError.intentionalFailure }
        isRunning = true
    }

    public func stop() {
        stopCallCount += 1
        isRunning = false
    }

    public func reset() {
        startCallCount    = 0
        stopCallCount     = 0
        isRunning         = false
        shouldThrowOnStart = false
    }
}
