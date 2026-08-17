import Foundation
import IOKit.pwr_mgt
import OSLog

/// A fine-grained RAII wrapper around a single `IOPMAssertion`.
///
/// Owns exactly one assertion; releases it on `deinit` or explicit `release()`.
/// Thread-safe via `NSLock`.
public final class PowerAssertion: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "PowerAssertion")
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private let lock = NSLock()

    public var isActive: Bool {
        lock.withLock { assertionID != IOPMAssertionID(0) }
    }

    public init() {}

    /// Create an IOPMAssertion of the given type.
    /// - Parameters:
    ///   - type:   A CFString IOPMAssertion type constant (e.g. `kIOPMAssertionTypeNoIdleSleep`).
    ///   - level:  Assertion level — normally `kIOPMAssertionLevelOn`.
    ///   - reason: Human-readable reason string visible in Console.
    /// - Throws: `SleepPreventionError.assertionDenied` if the OS refuses.
    public func create(
        type:   CFString,
        level:  IOPMAssertionLevel = IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reason: String
    ) throws {
        try lock.withLock {
            guard assertionID == IOPMAssertionID(0) else { return }
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(type, level, reason as CFString, &id)
            guard result == kIOReturnSuccess else {
                logger.error("IOPMAssertion creation denied (code: \(result))")
                throw SleepPreventionError.assertionDenied(code: result)
            }
            assertionID = id
            logger.debug("PowerAssertion created (id: \(id))")
        }
    }

    /// Release the assertion. Safe to call multiple times.
    public func release() {
        lock.withLock {
            guard assertionID != IOPMAssertionID(0) else { return }
            IOPMAssertionRelease(assertionID)
            logger.debug("PowerAssertion released (id: \(self.assertionID))")
            assertionID = IOPMAssertionID(0)
        }
    }

    deinit { release() }
}
