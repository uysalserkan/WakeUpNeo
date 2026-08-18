import XCTest
@testable import WakeUpNeoCore

final class SemanticVersionTests: XCTestCase {

    // MARK: - Parsing Tests

    func testStandardVersionParsing() {
        let v = SemanticVersion("1.2.3")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 2)
        XCTAssertEqual(v?.patch, 3)
        XCTAssertNil(v?.prerelease)
    }

    func testVersionWithLeadingV() {
        let v = SemanticVersion("v1.0.4")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 0)
        XCTAssertEqual(v?.patch, 4)
        XCTAssertNil(v?.prerelease)

        let upperV = SemanticVersion("V2.1.0")
        XCTAssertNotNil(upperV)
        XCTAssertEqual(upperV?.major, 2)
        XCTAssertEqual(upperV?.minor, 1)
        XCTAssertEqual(upperV?.patch, 0)
    }

    func testTwoComponentVersion() {
        let v = SemanticVersion("1.5")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 5)
        XCTAssertEqual(v?.patch, 0)
    }

    func testSingleComponentVersion() {
        let v = SemanticVersion("2")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 2)
        XCTAssertEqual(v?.minor, 0)
        XCTAssertEqual(v?.patch, 0)
    }

    func testVersionWithPrerelease() {
        let v = SemanticVersion("1.0.0-beta.1")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 0)
        XCTAssertEqual(v?.patch, 0)
        XCTAssertEqual(v?.prerelease, "beta.1")
    }

    func testVersionWithBuildMetadata() {
        let v = SemanticVersion("1.0.0+20130313144700")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 0)
        XCTAssertEqual(v?.patch, 0)
    }

    func testInvalidVersionStrings() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("   "))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion("v"))
    }

    // MARK: - Comparison Tests

    func testMajorVersionComparison() {
        let v1 = SemanticVersion("1.0.0")!
        let v2 = SemanticVersion("2.0.0")!
        XCTAssertTrue(v1 < v2)
        XCTAssertFalse(v2 < v1)
        XCTAssertTrue(v2 > v1)
    }

    func testMinorVersionComparison() {
        let v1 = SemanticVersion("1.0.4")!
        let v2 = SemanticVersion("1.1.0")!
        XCTAssertTrue(v1 < v2)
        XCTAssertTrue(v2 > v1)
    }

    func testPatchVersionComparison() {
        let v1 = SemanticVersion("1.0.4")!
        let v2 = SemanticVersion("1.0.5")!
        XCTAssertTrue(v1 < v2)
        XCTAssertTrue(v2 > v1)
        XCTAssertEqual(v1, SemanticVersion("v1.0.4"))
    }

    func testPrereleaseComparison() {
        let release = SemanticVersion("1.0.0")!
        let prerelease = SemanticVersion("1.0.0-alpha")!
        let beta = SemanticVersion("1.0.0-beta")!

        XCTAssertTrue(prerelease < release)
        XCTAssertTrue(prerelease < beta)
        XCTAssertTrue(beta < release)
    }

    func testEquality() {
        let v1 = SemanticVersion("1.0.4")!
        let v2 = SemanticVersion("v1.0.4")!
        XCTAssertEqual(v1, v2)
        XCTAssertEqual(v1.description, "1.0.4")
    }
}
