import Foundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.wakeupneo.app", category: "ProcessWatcher")

// MARK: - MonitoredProcessInfo

/// Represents a running application or process available for monitoring.
public struct MonitoredProcessInfo: Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let name: String
    public let bundleIdentifier: String?
    public let isRegularApp: Bool

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, bundleIdentifier: String? = nil, isRegularApp: Bool = true) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isRegularApp = isRegularApp
    }
}

// MARK: - ProcessWatcherError

public enum ProcessWatcherError: Error, LocalizedError, Sendable {
    case processNotFound(Int32)
    case alreadyWatching

    public var errorDescription: String? {
        switch self {
        case .processNotFound(let pid):
            return "Process with PID \(pid) is not running."
        case .alreadyWatching:
            return "Application / Process monitoring is already active."
        }
    }
}

// MARK: - ProcessWatchingService Protocol

public protocol ProcessWatchingService: Sendable {
    var isWatching: Bool { get }

    /// Returns the list of currently running user applications.
    func runningApplications() -> [MonitoredProcessInfo]

    /// Checks if a process with the given PID is currently alive.
    func isProcessAlive(pid: Int32) -> Bool

    /// Starts monitoring a process by PID until it terminates.
    func watchProcess(
        pid: Int32,
        name: String,
        onTerminate: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws

    /// Stops any active process monitoring.
    func stop()
}

// MARK: - DefaultProcessWatchingService

public final class DefaultProcessWatchingService: ProcessWatchingService, @unchecked Sendable {

    private let lock = NSLock()
    private var activePID: Int32?
    private var processSource: (any DispatchSourceProcess)?
    private var pollingTimer: (any DispatchSourceTimer)?
    private var workspaceObserver: NSObjectProtocol?
    private let monitoringQueue = DispatchQueue(label: "com.wakeupneo.processwatcher", qos: .utility)

    public var isWatching: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activePID != nil
    }

    public init() {}

    deinit {
        stop()
    }

    // MARK: - Running Applications Discovery

    public func runningApplications() -> [MonitoredProcessInfo] {
        let apps = NSWorkspace.shared.runningApplications
        var list: [MonitoredProcessInfo] = []

        for app in apps {
            guard app.processIdentifier > 0,
                  let name = app.localizedName,
                  !name.isEmpty else { continue }

            // Filter out current app to avoid monitoring ourselves
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                continue
            }

            let isRegular = app.activationPolicy == .regular
            list.append(MonitoredProcessInfo(
                pid: app.processIdentifier,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                isRegularApp: isRegular
            ))
        }

        // Sort regular apps first, then alphabetically by name
        return list.sorted { lhs, rhs in
            if lhs.isRegularApp != rhs.isRegularApp {
                return lhs.isRegularApp && !rhs.isRegularApp
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Process Liveness Check

    public func isProcessAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        // Check NSRunningApplication first for GUI apps
        if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            return true
        }
        // Fallback to POSIX kill(pid, 0) for non-GUI or command-line processes
        let result = kill(pid, 0)
        return result == 0 || errno == EPERM
    }

    // MARK: - Process Monitoring

    public func watchProcess(
        pid: Int32,
        name: String,
        onTerminate: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard activePID == nil else {
            throw ProcessWatcherError.alreadyWatching
        }

        guard isProcessAlive(pid: pid) else {
            throw ProcessWatcherError.processNotFound(pid)
        }

        activePID = pid

        // 1. Kernel-level DispatchSourceProcess on NOTE_EXIT
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: monitoringQueue
        )

        source.setEventHandler { [weak self] in
            logger.info("DispatchSourceProcess detected termination of PID \(pid)")
            self?.handleTermination(pid: pid, onTerminate: onTerminate)
        }

        source.setCancelHandler {
            logger.debug("DispatchSourceProcess cancelled for PID \(pid)")
        }

        source.resume()
        processSource = source

        // 2. NSWorkspace termination observer (for GUI apps)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == pid else { return }
            logger.info("NSWorkspace didTerminateApplicationNotification received for PID \(pid)")
            self?.handleTermination(pid: pid, onTerminate: onTerminate)
        }

        // 3. Fallback Periodic Polling Timer (guarantees detection across permission boundaries)
        let timer = DispatchSource.makeTimerSource(queue: monitoringQueue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1), leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if !self.isProcessAlive(pid: pid) {
                logger.info("Fallback polling timer detected dead PID \(pid)")
                self.handleTermination(pid: pid, onTerminate: onTerminate)
            }
        }
        timer.resume()
        pollingTimer = timer

        logger.info("Started watching process '\(name)' (PID \(pid))")
    }

    // MARK: - Termination & Cleanup

    private func handleTermination(
        pid: Int32,
        onTerminate: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        guard activePID == pid else {
            lock.unlock()
            return
        }
        cleanupInternal()
        lock.unlock()

        logger.info("Process '\(pid)' terminated — triggering onTerminate callback")
        onTerminate()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        cleanupInternal()
    }

    private func cleanupInternal() {
        if let source = processSource {
            source.cancel()
            processSource = nil
        }
        if let timer = pollingTimer {
            timer.cancel()
            pollingTimer = nil
        }
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        activePID = nil
    }
}
