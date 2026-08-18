import Foundation

// MARK: - GitHubReleaseAsset

/// An asset attached to a GitHub release (e.g. `.dmg` or `.zip`).
public struct GitHubReleaseAsset: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: Int
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int
    public let contentType: String?
    public let downloadCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
        case downloadCount = "download_count"
    }

    public init(
        id: Int,
        name: String,
        browserDownloadURL: URL,
        size: Int = 0,
        contentType: String? = nil,
        downloadCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
        self.contentType = contentType
        self.downloadCount = downloadCount
    }
}

// MARK: - GitHubRelease

/// Represents a GitHub release object returned by the GitHub API.
public struct GitHubRelease: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: Int
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let publishedAt: Date?
    public let isPrerelease: Bool
    public let isDraft: Bool
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case isPrerelease = "prerelease"
        case isDraft = "draft"
        case assets
    }

    public init(
        id: Int,
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlURL: URL,
        publishedAt: Date? = nil,
        isPrerelease: Bool = false,
        isDraft: Bool = false,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.id = id
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.isPrerelease = isPrerelease
        self.isDraft = isDraft
        self.assets = assets
    }

    /// Parsed semantic version from `tagName`.
    public var semanticVersion: SemanticVersion? {
        SemanticVersion(tagName)
    }

    /// Display title for the release (defaults to tagName if name is missing or empty).
    public var displayTitle: String {
        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return tagName
    }

    /// The first `.dmg` asset found, if any.
    public var dmgAsset: GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }

    /// The first `.zip` asset found, if any.
    public var zipAsset: GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }

    /// The preferred download URL: first DMG asset, then Zip asset, falling back to htmlURL.
    public var preferredDownloadURL: URL {
        dmgAsset?.browserDownloadURL ?? zipAsset?.browserDownloadURL ?? htmlURL
    }
}

// MARK: - UpdateCheckResult

/// Outcome of comparing the running app version with the latest release.
public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(currentVersion: SemanticVersion)
    case updateAvailable(latestRelease: GitHubRelease, currentVersion: SemanticVersion)

    public var isUpdateAvailable: Bool {
        if case .updateAvailable = self {
            return true
        }
        return false
    }

    public var latestRelease: GitHubRelease? {
        if case .updateAvailable(let release, _) = self {
            return release
        }
        return nil
    }
}
