import Foundation

// MARK: - SemanticVersion

/// A semantic version representation supporting comparison and parsing of version strings.
///
/// Handles versions with or without a leading 'v' or 'V' prefix (e.g., "v1.0.4", "1.0.4", "2.0", "1.0.5-beta.1").
public struct SemanticVersion: Comparable, Equatable, Hashable, Sendable, Codable, CustomStringConvertible {

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let rawString: String

    public var description: String {
        var result = "\(major).\(minor).\(patch)"
        if let prerelease = prerelease, !prerelease.isEmpty {
            result += "-\(prerelease)"
        }
        return result
    }

    // MARK: - Initializers

    public init(major: Int, minor: Int = 0, patch: Int = 0, prerelease: String? = nil, rawString: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawString = rawString ?? "\(major).\(minor).\(patch)\(prerelease != nil ? "-\(prerelease!)" : "")"
    }

    /// Parses a version string into a `SemanticVersion`.
    /// Returns `nil` if the string cannot be parsed as a valid version.
    public init?(_ versionString: String) {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip leading 'v' or 'V'
        var normalized = trimmed
        if normalized.hasPrefix("v") || normalized.hasPrefix("V") {
            normalized.removeFirst()
        }

        // Split prerelease if present (e.g. "1.0.0-beta.1" or "1.0.0+build1")
        var prereleasePart: String?
        if let hyphenIndex = normalized.firstIndex(of: "-") {
            prereleasePart = String(normalized[normalized.index(after: hyphenIndex)...])
            normalized = String(normalized[..<hyphenIndex])
        } else if let plusIndex = normalized.firstIndex(of: "+") {
            // Build metadata ignored for version comparison but preserved
            normalized = String(normalized[..<plusIndex])
        }

        let components = normalized.split(separator: ".").compactMap { Int($0) }
        guard !components.isEmpty else { return nil }

        self.major = components[0]
        self.minor = components.count > 1 ? components[1] : 0
        self.patch = components.count > 2 ? components[2] : 0
        self.prerelease = prereleasePart
        self.rawString = trimmed
    }

    // MARK: - Comparable

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // Pre-release versions have lower precedence than normal release versions.
        // E.g., 1.0.0-alpha < 1.0.0
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            return true  // lhs is prerelease, rhs is release -> lhs < rhs
        case (nil, .some):
            return false // lhs is release, rhs is prerelease -> lhs > rhs
        case let (lhsPre?, rhsPre?):
            return lhsPre.localizedStandardCompare(rhsPre) == .orderedAscending
        }
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major &&
        lhs.minor == rhs.minor &&
        lhs.patch == rhs.patch &&
        lhs.prerelease == rhs.prerelease
    }
}
