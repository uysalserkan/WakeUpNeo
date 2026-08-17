import Foundation

// MARK: - DefaultDuration

/// The standard preset durations shown in the menu bar picker.
public enum DefaultDuration: TimeInterval, CaseIterable, Identifiable, Sendable, Codable {
    case fifteenMinutes = 900
    case thirtyMinutes  = 1800
    case oneHour        = 3600
    case twoHours       = 7200

    public var id: TimeInterval { rawValue }

    public var label: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes:  return "30 minutes"
        case .oneHour:        return "1 hour"
        case .twoHours:       return "2 hours"
        }
    }

    public var shortLabel: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes:  return "30m"
        case .oneHour:        return "1h"
        case .twoHours:       return "2h"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .fifteenMinutes: return "Start for 15 minutes"
        case .thirtyMinutes:  return "Start for 30 minutes"
        case .oneHour:        return "Start for 1 hour"
        case .twoHours:       return "Start for 2 hours"
        }
    }
}

// MARK: - UserDefaults Keys

/// Centralised UserDefaults keys to prevent stringly-typed bugs.
/// Used both by @AppStorage in the views and by AppSettings in tests.
public enum AppSettingsKeys {
    public static let launchAtLogin              = "launchAtLogin"
    public static let showCountdownInMenuBar     = "showCountdownInMenuBar"
    public static let defaultDuration            = "defaultDuration"
    public static let notifyOnSessionEnd         = "notifyOnSessionEnd"
    public static let notifyOnSessionExpiring    = "notifyOnSessionExpiring"
    public static let preventSystemSleep         = "preventSystemSleep"
    public static let keepDisplayAwake           = "keepDisplayAwake"
    public static let preventLidSleep            = "preventLidSleep"
    // Smart Watcher Preferences
    public static let watchedDownloadsPath       = "watchedDownloadsPath"
    public static let customTemporaryExtensions  = "customTemporaryExtensions"
    public static let fileStabilizationDuration  = "fileStabilizationDuration"
    public static let notifyOnDownloadsComplete  = "notifyOnDownloadsComplete"
    public static let notifyOnFileDetected       = "notifyOnFileDetected"
}

// MARK: - AppSettings (testable snapshot)

/// A plain-struct snapshot of persisted settings, used for testing
/// without touching the live UserDefaults suite.
public struct AppSettings: Equatable, Sendable {
    public var launchAtLogin:              Bool
    public var showCountdownInMenuBar:     Bool
    public var defaultDuration:            DefaultDuration
    public var notifyOnSessionEnd:         Bool
    public var notifyOnSessionExpiring:    Bool
    public var preventSystemSleep:         Bool
    public var keepDisplayAwake:           Bool
    public var preventLidSleep:            Bool
    public var watchedDownloadsPath:       String
    public var customTemporaryExtensions:  String
    public var fileStabilizationDuration:  Double
    public var notifyOnDownloadsComplete:  Bool
    public var notifyOnFileDetected:       Bool

    /// The standard user Downloads directory URL.
    public static var defaultDownloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    public static let `default` = AppSettings(
        launchAtLogin:              true,
        showCountdownInMenuBar:     true,
        defaultDuration:            .oneHour,
        notifyOnSessionEnd:         true,
        notifyOnSessionExpiring:    false,
        preventSystemSleep:         true,
        keepDisplayAwake:           false,
        preventLidSleep:            false,
        watchedDownloadsPath:       AppSettings.defaultDownloadsURL.path(percentEncoded: false),
        customTemporaryExtensions:  "",
        fileStabilizationDuration:  2.0,
        notifyOnDownloadsComplete:  true,
        notifyOnFileDetected:       true
    )

    public init(
        launchAtLogin:              Bool            = true,
        showCountdownInMenuBar:     Bool            = true,
        defaultDuration:            DefaultDuration = .oneHour,
        notifyOnSessionEnd:         Bool            = true,
        notifyOnSessionExpiring:    Bool            = false,
        preventSystemSleep:         Bool            = true,
        keepDisplayAwake:           Bool            = false,
        preventLidSleep:            Bool            = false,
        watchedDownloadsPath:       String?         = nil,
        customTemporaryExtensions:  String          = "",
        fileStabilizationDuration:  Double          = 2.0,
        notifyOnDownloadsComplete:  Bool            = true,
        notifyOnFileDetected:       Bool            = true
    ) {
        self.launchAtLogin              = launchAtLogin
        self.showCountdownInMenuBar     = showCountdownInMenuBar
        self.defaultDuration            = defaultDuration
        self.notifyOnSessionEnd         = notifyOnSessionEnd
        self.notifyOnSessionExpiring    = notifyOnSessionExpiring
        self.preventSystemSleep         = preventSystemSleep
        self.keepDisplayAwake           = keepDisplayAwake
        self.preventLidSleep            = preventLidSleep
        self.watchedDownloadsPath       = watchedDownloadsPath ?? AppSettings.defaultDownloadsURL.path(percentEncoded: false)
        self.customTemporaryExtensions  = customTemporaryExtensions
        self.fileStabilizationDuration  = fileStabilizationDuration
        self.notifyOnDownloadsComplete  = notifyOnDownloadsComplete
        self.notifyOnFileDetected       = notifyOnFileDetected
    }

    /// Convenience URL representation of `watchedDownloadsPath`.
    public var watchedDownloadsURL: URL {
        URL(fileURLWithPath: watchedDownloadsPath)
    }

    /// Set of parsed custom extensions from the comma-delimited string.
    public var parsedCustomExtensions: Set<String> {
        let parts = customTemporaryExtensions
            .split(separator: ",")
            .map { DownloadPatternMatcher.normalizeExtension(String($0)) }
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    /// Load current values from the standard UserDefaults suite.
    public static func load() -> AppSettings {
        let d = UserDefaults.standard
        let raw = d.double(forKey: AppSettingsKeys.defaultDuration)
        let watchedPath = d.string(forKey: AppSettingsKeys.watchedDownloadsPath) ?? defaultDownloadsURL.path(percentEncoded: false)
        let customExt = d.string(forKey: AppSettingsKeys.customTemporaryExtensions) ?? ""
        let settleDuration = d.object(forKey: AppSettingsKeys.fileStabilizationDuration) == nil ? 2.0 : d.double(forKey: AppSettingsKeys.fileStabilizationDuration)

        return AppSettings(
            launchAtLogin:              d.object(forKey: AppSettingsKeys.launchAtLogin)              == nil ? true  : d.bool(forKey: AppSettingsKeys.launchAtLogin),
            showCountdownInMenuBar:     d.object(forKey: AppSettingsKeys.showCountdownInMenuBar)     == nil ? true  : d.bool(forKey: AppSettingsKeys.showCountdownInMenuBar),
            defaultDuration:            DefaultDuration(rawValue: raw) ?? .oneHour,
            notifyOnSessionEnd:         d.object(forKey: AppSettingsKeys.notifyOnSessionEnd)         == nil ? true  : d.bool(forKey: AppSettingsKeys.notifyOnSessionEnd),
            notifyOnSessionExpiring:    d.bool(forKey: AppSettingsKeys.notifyOnSessionExpiring),
            preventSystemSleep:         d.object(forKey: AppSettingsKeys.preventSystemSleep)         == nil ? true  : d.bool(forKey: AppSettingsKeys.preventSystemSleep),
            keepDisplayAwake:           d.bool(forKey: AppSettingsKeys.keepDisplayAwake),
            preventLidSleep:            d.bool(forKey: AppSettingsKeys.preventLidSleep),
            watchedDownloadsPath:       watchedPath,
            customTemporaryExtensions:  customExt,
            fileStabilizationDuration:  settleDuration,
            notifyOnDownloadsComplete:  d.object(forKey: AppSettingsKeys.notifyOnDownloadsComplete)  == nil ? true  : d.bool(forKey: AppSettingsKeys.notifyOnDownloadsComplete),
            notifyOnFileDetected:       d.object(forKey: AppSettingsKeys.notifyOnFileDetected)       == nil ? true  : d.bool(forKey: AppSettingsKeys.notifyOnFileDetected)
        )
    }
}
