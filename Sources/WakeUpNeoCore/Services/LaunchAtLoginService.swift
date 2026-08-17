import Foundation
import ServiceManagement
import OSLog

// MARK: - Protocol

/// The contract for the launch-at-login service, enabling a mock in tests.
public protocol LaunchAtLoginServiceProtocol: Sendable {
    var isEnabled: Bool { get }
    func enable() throws
    func disable() throws
}

// MARK: - LaunchAtLoginService

/// Registers and unregisters the app as a login item via `SMAppService`.
///
/// Uses Apple's `ServiceManagement` framework (macOS 13+). No shell scripts,
/// no LaunchAgent plists — just the system API.
public final class LaunchAtLoginService: LaunchAtLoginServiceProtocol, Sendable {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "LaunchAtLogin")

    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func enable() throws {
        logger.info("Registering as login item")
        do {
            try SMAppService.mainApp.register()
            logger.info("Login item registered")
        } catch {
            logger.error("Failed to register login item: \(error)")
            throw error
        }
    }

    public func disable() throws {
        logger.info("Unregistering login item")
        do {
            try SMAppService.mainApp.unregister()
            logger.info("Login item unregistered")
        } catch {
            logger.error("Failed to unregister login item: \(error)")
            throw error
        }
    }
}
