import Foundation
import OSLog
import IOKit.pwr_mgt

// MARK: - SleepPreventionService Protocol

/// The contract every sleep-prevention backend must satisfy.
///
/// The rest of the application never touches IOKit or ProcessInfo directly.
/// All power-management operations route through this protocol, which makes
/// the power-management layer fully testable via mocks.
public protocol SleepPreventionService: Sendable {
    /// Activate sleep prevention. Throws if the OS refuses the assertion.
    func start() throws
    /// Release the active assertion. Safe to call when already stopped.
    func stop()
    /// Whether an assertion is currently held.
    var isRunning: Bool { get }
}

// MARK: - SleepPreventionError

public enum SleepPreventionError: Error, LocalizedError, Sendable {
    case assertionDenied(code: IOReturn)
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .assertionDenied:
            return "macOS did not allow the requested power assertion. Try again, or check System Settings › Energy Saver."
        case .alreadyRunning:
            return "Sleep prevention is already active."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .assertionDenied:
            return "Make sure Low Power Mode is not forcing sleep, and that the app has the necessary entitlements."
        case .alreadyRunning:
            return "Stop the current session before starting a new one."
        }
    }
}

// MARK: - ProcessInfoSleepService

/// Prevents idle **system** sleep via `ProcessInfo.beginActivity`.
///
/// This is the simplest and most portable approach. It does not require
/// any special entitlements and works reliably on all supported macOS versions.
///
/// Safety: All public methods are expected to be called from the main actor
/// (via SleepManager). The class is marked `@unchecked Sendable` because
/// `NSObjectProtocol` is not `Sendable`, but access is serialised by the caller.
public final class ProcessInfoSleepService: SleepPreventionService, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "ProcessInfoSleepService")
    private var activity: NSObjectProtocol?
    private let options: ProcessInfo.ActivityOptions
    private let reason: String

    public var isRunning: Bool { activity != nil }

    public init(
        options: ProcessInfo.ActivityOptions = [.idleSystemSleepDisabled],
        reason: String = "WakeUpNeo: Preventing idle system sleep"
    ) {
        self.options = options
        self.reason  = reason
    }

    public func start() throws {
        guard activity == nil else { return }
        logger.info("[Power] Starting sleep prevention (ProcessInfo)")
        activity = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        logger.info("[Power] Assertion created (ProcessInfo)")
    }

    public func stop() {
        guard let current = activity else { return }
        logger.info("[Power] Releasing assertion (ProcessInfo)")
        ProcessInfo.processInfo.endActivity(current)
        activity = nil
        logger.info("[Power] Assertion released (ProcessInfo)")
    }
}

// MARK: - IOKitAssertionType

/// The independent sleep-prevention assertion types WakeUpNeo supports.
public enum IOKitAssertionType: Sendable {
    /// Prevent the system from sleeping due to user inactivity.
    case preventIdleSystemSleep
    /// Prevent the display from sleeping due to user inactivity.
    case preventIdleDisplaySleep
    /// Prevent the system from sleeping when the lid is closed (or general system sleep).
    case preventSystemSleep

    var cfString: CFString {
        switch self {
        case .preventIdleSystemSleep:  return kIOPMAssertionTypeNoIdleSleep  as CFString
        case .preventIdleDisplaySleep: return kIOPMAssertionTypeNoDisplaySleep as CFString
        case .preventSystemSleep:      return kIOPMAssertionTypePreventSystemSleep as CFString
        }
    }

    var logName: String {
        switch self {
        case .preventIdleSystemSleep:  return "NoIdleSleep"
        case .preventIdleDisplaySleep: return "NoDisplaySleep"
        case .preventSystemSleep:      return "PreventSystemSleep"
        }
    }
}

// MARK: - IOKitSleepService

/// Prevents sleep via a low-level `IOPMAssertion`.
///
/// Prefer this over `ProcessInfoSleepService` when you need independent
/// control over system sleep, display sleep, and lid-close sleep, because
/// IOKit allows one assertion per behaviour.
///
/// Safety: Same threading contract as `ProcessInfoSleepService`.
public final class IOKitSleepService: SleepPreventionService, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "IOKitSleepService")
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private let assertionType: IOKitAssertionType
    private let reason: String

    public var isRunning: Bool { assertionID != IOPMAssertionID(0) }

    public init(
        assertionType: IOKitAssertionType = .preventIdleSystemSleep,
        reason: String = "WakeUpNeo: Preventing idle sleep"
    ) {
        self.assertionType = assertionType
        self.reason        = reason
    }

    public func start() throws {
        guard assertionID == IOPMAssertionID(0) else { return }
        logger.info("[Power] Starting sleep prevention (IOKit/\(self.assertionType.logName))")
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            assertionType.cfString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            logger.error("[Power] IOKit assertion denied (code: \(result))")
            throw SleepPreventionError.assertionDenied(code: result)
        }
        assertionID = id
        logger.info("[Power] Assertion created (IOKit/\(self.assertionType.logName), id: \(id))")
    }

    public func stop() {
        guard assertionID != IOPMAssertionID(0) else { return }
        logger.info("[Power] Releasing assertion (IOKit/\(self.assertionType.logName), id: \(self.assertionID))")
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        logger.info("[Power] Assertion released (IOKit/\(self.assertionType.logName))")
    }

    deinit { stop() }
}

// MARK: - CompositeSleepService

/// Owns independent `SleepPreventionService` instances — system sleep,
/// display sleep, and lid-close sleep — so they can be toggled independently.
///
/// This is the service type injected into `SleepManager`.
public final class CompositeSleepService: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "CompositeSleepService")

    public let systemSleepService:  any SleepPreventionService
    public let displaySleepService: any SleepPreventionService
    public let lidSleepService:     any SleepPreventionService

    public init(
        systemSleepService:  any SleepPreventionService,
        displaySleepService: any SleepPreventionService,
        lidSleepService:     any SleepPreventionService = IOKitSleepService(assertionType: .preventSystemSleep, reason: "WakeUpNeo: Preventing lid-close sleep")
    ) {
        self.systemSleepService  = systemSleepService
        self.displaySleepService = displaySleepService
        self.lidSleepService     = lidSleepService
    }

    public func startSystemSleep() throws {
        logger.info("[Power] Starting system sleep assertion")
        try systemSleepService.start()
    }

    public func stopSystemSleep() {
        systemSleepService.stop()
    }

    public func startDisplaySleep() throws {
        logger.info("[Power] Starting display sleep assertion")
        try displaySleepService.start()
    }

    public func stopDisplaySleep() {
        displaySleepService.stop()
    }

    public func startLidSleep() throws {
        logger.info("[Power] Starting lid-close sleep assertion")
        try lidSleepService.start()
    }

    public func stopLidSleep() {
        lidSleepService.stop()
    }

    /// Release every held assertion. Idempotent.
    public func stopAll() {
        logger.info("[Power] Session ending - stopping all assertions")
        systemSleepService.stop()
        displaySleepService.stop()
        lidSleepService.stop()
    }
}
