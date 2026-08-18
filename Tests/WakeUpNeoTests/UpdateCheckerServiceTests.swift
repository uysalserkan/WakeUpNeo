import XCTest
@testable import WakeUpNeoCore

// MARK: - MockDataFetcher

final class MockDataFetcher: HTTPDataFetching, @unchecked Sendable {
    var responseData: Data?
    var responseCode: Int = 200
    var errorToThrow: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = errorToThrow {
            throw error
        }

        let url = request.url ?? URL(string: "https://api.github.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: responseCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let data = responseData ?? Data()
        return (data, response)
    }
}

// MARK: - UpdateCheckerServiceTests

final class UpdateCheckerServiceTests: XCTestCase {

    private func makeReleaseJSON(
        tagName: String,
        name: String = "WakeUpNeo Release",
        body: String = "Bug fixes and improvements",
        isPrerelease: Bool = false,
        isDraft: Bool = false,
        assets: [[String: Any]] = []
    ) -> Data {
        let dict: [String: Any] = [
            "id": 12345,
            "tag_name": tagName,
            "name": name,
            "body": body,
            "html_url": "https://github.com/uysalserkan/wakeupneo/releases/tag/\(tagName)",
            "published_at": "2026-08-18T10:00:00Z",
            "prerelease": isPrerelease,
            "draft": isDraft,
            "assets": assets
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    func testNewerVersionDetected() async throws {
        let mockFetcher = MockDataFetcher()
        mockFetcher.responseData = makeReleaseJSON(
            tagName: "v1.0.5",
            name: "WakeUpNeo 1.0.5",
            assets: [
                [
                    "id": 1,
                    "name": "WakeUpNeo.dmg",
                    "browser_download_url": "https://github.com/uysalserkan/wakeupneo/releases/download/v1.0.5/WakeUpNeo.dmg",
                    "size": 2048000,
                    "download_count": 42
                ]
            ]
        )

        let service = UpdateCheckerService(dataFetcher: mockFetcher)
        let result = try await service.checkForUpdates(currentVersionString: "1.0.4")

        XCTAssertTrue(result.isUpdateAvailable)
        guard case .updateAvailable(let release, let current) = result else {
            XCTFail("Expected .updateAvailable but got \(result)")
            return
        }

        XCTAssertEqual(release.tagName, "v1.0.5")
        XCTAssertEqual(release.displayTitle, "WakeUpNeo 1.0.5")
        XCTAssertEqual(current.description, "1.0.4")
        XCTAssertEqual(release.dmgAsset?.name, "WakeUpNeo.dmg")
        XCTAssertEqual(
            release.preferredDownloadURL.absoluteString,
            "https://github.com/uysalserkan/wakeupneo/releases/download/v1.0.5/WakeUpNeo.dmg"
        )
    }

    func testSameVersionIsUpToDate() async throws {
        let mockFetcher = MockDataFetcher()
        mockFetcher.responseData = makeReleaseJSON(tagName: "v1.0.4")

        let service = UpdateCheckerService(dataFetcher: mockFetcher)
        let result = try await service.checkForUpdates(currentVersionString: "1.0.4")

        XCTAssertFalse(result.isUpdateAvailable)
        guard case .upToDate(let current) = result else {
            XCTFail("Expected .upToDate but got \(result)")
            return
        }
        XCTAssertEqual(current.description, "1.0.4")
    }

    func testOlderReleaseIsUpToDate() async throws {
        let mockFetcher = MockDataFetcher()
        mockFetcher.responseData = makeReleaseJSON(tagName: "v1.0.3")

        let service = UpdateCheckerService(dataFetcher: mockFetcher)
        let result = try await service.checkForUpdates(currentVersionString: "1.0.4")

        XCTAssertFalse(result.isUpdateAvailable)
    }

    func testPrereleaseIgnoredByDefault() async throws {
        let mockFetcher = MockDataFetcher()
        mockFetcher.responseData = makeReleaseJSON(tagName: "v1.0.5-beta.1", isPrerelease: true)

        let service = UpdateCheckerService(dataFetcher: mockFetcher)
        let result = try await service.checkForUpdates(currentVersionString: "1.0.4", includePrereleases: false)

        XCTAssertFalse(result.isUpdateAvailable)
    }

    func testDraftReleaseIgnored() async throws {
        let mockFetcher = MockDataFetcher()
        mockFetcher.responseData = makeReleaseJSON(tagName: "v2.0.0", isDraft: true)

        let service = UpdateCheckerService(dataFetcher: mockFetcher)
        let result = try await service.checkForUpdates(currentVersionString: "1.0.4")

        XCTAssertFalse(result.isUpdateAvailable)
    }

    func testHttpErrorThrows() async {
        let mockFetcher = MockDataFetcher()
        mockFetcher.responseCode = 404
        mockFetcher.responseData = "Not Found".data(using: .utf8)

        let service = UpdateCheckerService(dataFetcher: mockFetcher)

        do {
            _ = try await service.checkForUpdates(currentVersionString: "1.0.4")
            XCTFail("Expected error to be thrown")
        } catch let error as UpdateCheckerError {
            if case .httpError(let code, _) = error {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedJSONThrows() async {
        let mockFetcher = MockDataFetcher()
        mockFetcher.responseData = "{ invalid json".data(using: .utf8)

        let service = UpdateCheckerService(dataFetcher: mockFetcher)

        do {
            _ = try await service.checkForUpdates(currentVersionString: "1.0.4")
            XCTFail("Expected decoding error to be thrown")
        } catch let error as UpdateCheckerError {
            if case .decodingError = error {
                // Success
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
