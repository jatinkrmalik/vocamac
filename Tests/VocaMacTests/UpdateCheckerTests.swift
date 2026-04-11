// UpdateCheckerTests.swift
// VocaMac Tests

import XCTest
@testable import VocaMac

final class UpdateCheckerTests: XCTestCase {
    @MainActor
    func testNormalizeVersionStripsVPrefix() {
        let checker = UpdateChecker()
        XCTAssertEqual(checker.normalizeVersion("v0.4.0"), "0.4.0")
    }

    @MainActor
    func testNormalizeVersionPadsMissingSegments() {
        let checker = UpdateChecker()
        XCTAssertEqual(checker.normalizeVersion("1"), "1.0.0")
        XCTAssertEqual(checker.normalizeVersion("1.2"), "1.2.0")
    }

    @MainActor
    func testVersionComparisonHandlesTwoDigitMinor() {
        let checker = UpdateChecker()
        XCTAssertTrue(checker.isNewerVersion(remote: "0.10.0", current: "0.9.0"))
        XCTAssertFalse(checker.isNewerVersion(remote: "0.9.0", current: "0.10.0"))
    }

    func testGitHubReleaseDecoding() throws {
        let json = #"{"tag_name":"v0.4.0","name":"v0.4.0-beta","body":"Release notes","html_url":"https://github.com/jatinkrmalik/vocamac/releases/tag/v0.4.0","prerelease":false,"draft":false,"published_at":"2026-04-10T18:46:58Z","assets":[{"name":"VocaMac-0.4.0-arm64.dmg","size":1234,"browser_download_url":"https://github.com/jatinkrmalik/vocamac/releases/download/v0.4.0/VocaMac-0.4.0-arm64.dmg","content_type":"application/x-apple-diskimage","digest":"sha256:abc123"}]}"#

        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(release.tagName, "v0.4.0")
        XCTAssertEqual(release.assets.count, 1)
        XCTAssertEqual(release.assets.first?.name, "VocaMac-0.4.0-arm64.dmg")
    }
}
