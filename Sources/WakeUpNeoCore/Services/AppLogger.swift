import Foundation
import os

/// Structured logger namespace for WakeUpNeo using Apple unified logging (`os.Logger`).
public enum AppLogger: Sendable {
    private static let subsystem = "com.wakeupneo.app"
    
    /// State machine transitions, session starts, stops, and lifecycle.
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    
    /// IOKit and ProcessInfo power assertion creation and release.
    public static let powerAssertion = Logger(subsystem: subsystem, category: "powerAssertion")
    
    /// Drift-free timer calculations, ticks, and expiration events.
    public static let timer = Logger(subsystem: subsystem, category: "timer")
    
    /// UserDefaults and persistent settings synchronization.
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    
    /// UserNotifications authorization and scheduling.
    public static let notification = Logger(subsystem: subsystem, category: "notification")
    
    /// UI events and popover interactions.
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
