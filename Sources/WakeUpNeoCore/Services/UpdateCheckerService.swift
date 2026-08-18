import Foundation
import OSLog

// MARK: - HTTPDataFetching

/// Abstraction over URLSession for deterministic testing.
public protocol HTTPDataFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataFetching {}

// MARK: - UpdateCheckerError

public enum UpdateCheckerError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case noReleaseFound
    case invalidCurrentVersion(String)
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid update check URL endpoint."
        case .invalidResponse:
            return "Received an invalid network response."
        case .httpError(let statusCode, let message):
            if let message = message, !message.isEmpty {
                return "HTTP \(statusCode): \(message)"
            }
            return "HTTP Error \(statusCode) while checking for updates."
        case .noReleaseFound:
            return "No releases found on GitHub."
        case .invalidCurrentVersion(let version):
            return "Unable to parse current application version: \(version)"
        case .decodingError(let details):
            return "Failed to parse release information: \(details)"
        }
    }
}

// MARK: - UpdateCheckerService

/// Checks GitHub releases API for newer versions of WakeUpNeo.
public final class UpdateCheckerService: Sendable {

    private let logger = Logger(subsystem: "com.wakeupneo.app", category: "UpdateChecker")

    public let owner: String
    public let repo: String
    private let dataFetcher: HTTPDataFetching

    public init(
        owner: String = "uysalserkan",
        repo: String = "wakeupneo",
        dataFetcher: HTTPDataFetching = URLSession.shared
    ) {
        self.owner = owner
        self.repo = repo
        self.dataFetcher = dataFetcher
    }

    /// The latest release endpoint URL for the repository.
    public var latestReleaseURL: URL? {
        URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
    }

    /// Fetches the latest published release from GitHub.
    public func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = latestReleaseURL else {
            throw UpdateCheckerError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WakeUpNeo", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15.0

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await dataFetcher.data(for: request)
        } catch {
            logger.error("Network error fetching release: \(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckerError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8)
            logger.error("GitHub API error status \(httpResponse.statusCode)")
            throw UpdateCheckerError.httpError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let release = try decoder.decode(GitHubRelease.self, from: data)
            return release
        } catch {
            logger.error("JSON decoding error: \(error.localizedDescription)")
            throw UpdateCheckerError.decodingError(error.localizedDescription)
        }
    }

    /// Checks whether an update is available compared to `currentVersionString`.
    public func checkForUpdates(
        currentVersionString: String,
        includePrereleases: Bool = false
    ) async throws -> UpdateCheckResult {
        guard let current = SemanticVersion(currentVersionString) else {
            throw UpdateCheckerError.invalidCurrentVersion(currentVersionString)
        }
        return try await checkForUpdates(currentVersion: current, includePrereleases: includePrereleases)
    }

    /// Checks whether an update is available compared to `currentVersion`.
    public func checkForUpdates(
        currentVersion: SemanticVersion,
        includePrereleases: Bool = false
    ) async throws -> UpdateCheckResult {
        let release = try await fetchLatestRelease()

        if release.isDraft {
            return .upToDate(currentVersion: currentVersion)
        }

        if release.isPrerelease && !includePrereleases {
            return .upToDate(currentVersion: currentVersion)
        }

        guard let releaseVersion = release.semanticVersion else {
            // Cannot parse tag into SemVer, treat as up to date
            logger.warning("Could not parse release tag '\(release.tagName)' as SemVer.")
            return .upToDate(currentVersion: currentVersion)
        }

        if releaseVersion > currentVersion {
            logger.info("Update available: \(releaseVersion.description) > \(currentVersion.description)")
            return .updateAvailable(latestRelease: release, currentVersion: currentVersion)
        } else {
            logger.info("Application is up to date: \(currentVersion.description) >= \(releaseVersion.description)")
            return .upToDate(currentVersion: currentVersion)
        }
    }
}
