import Foundation
import XCTest
@testable import QuotaBarCore

final class ReleaseVersionTests: XCTestCase {
    func testParsesTagPrefixAndMissingPatch() {
        XCTAssertEqual(ReleaseVersion("v0.3.0")?.description, "0.3.0")
        XCTAssertEqual(ReleaseVersion("1.2")?.description, "1.2.0")
    }

    func testRejectsMalformedVersions() {
        XCTAssertNil(ReleaseVersion(""))
        XCTAssertNil(ReleaseVersion("release-1.2.3"))
        XCTAssertNil(ReleaseVersion("1..3"))
        XCTAssertNil(ReleaseVersion("1.2.3.4"))
        XCTAssertNil(ReleaseVersion("1.2.3+"))
        XCTAssertNil(ReleaseVersion("1.2.3-beta!"))
    }

    func testComparesStableAndPrereleaseVersions() throws {
        let beta2 = try XCTUnwrap(ReleaseVersion("1.0.0-beta.2"))
        let beta10 = try XCTUnwrap(ReleaseVersion("1.0.0-beta.10"))
        let stable = try XCTUnwrap(ReleaseVersion("1.0.0"))
        let nextPatch = try XCTUnwrap(ReleaseVersion("1.0.1"))

        XCTAssertLessThan(beta2, beta10)
        XCTAssertLessThan(beta10, stable)
        XCTAssertLessThan(stable, nextPatch)
    }

    func testParsesTrustedGitHubRelease() throws {
        let data = Data(
            """
            {
              "tag_name": "v0.3.0",
              "html_url": "https://github.com/patrickradulescu/QuotaBar/releases/tag/v0.3.0",
              "draft": false,
              "prerelease": false
            }
            """.utf8
        )

        let release = try GitHubReleaseParser.parse(data: data)

        XCTAssertEqual(release.version, ReleaseVersion("0.3.0"))
        XCTAssertEqual(release.tagName, "v0.3.0")
    }

    func testRejectsUntrustedReleaseURL() {
        let untrustedURLs = [
            "https://example.com/QuotaBar.dmg",
            "https://github.com/patrickradulescu/QuotaBar/releases/tag/v1.0.0",
            "https://github.com/patrickradulescu/QuotaBar/releases/../../login",
            "https://github.com:8443/patrickradulescu/QuotaBar/releases/tag/v9.9.9",
            "https://github.com/patrickradulescu/QuotaBar/releases/tag/v9.9.9?download=1"
        ]

        for url in untrustedURLs {
            let data = Data(
                """
                {
                  "tag_name": "v9.9.9",
                  "html_url": "\(url)",
                  "draft": false,
                  "prerelease": false
                }
                """.utf8
            )

            XCTAssertThrowsError(try GitHubReleaseParser.parse(data: data)) { error in
                XCTAssertEqual(
                    error as? GitHubReleaseParser.ParseError,
                    .untrustedReleaseURL
                )
            }
        }
    }

    func testRejectsDraftAndPrereleaseResponses() {
        for key in ["draft", "prerelease"] {
            let data = Data(
                """
                {
                  "tag_name": "v0.4.0",
                  "html_url": "https://github.com/patrickradulescu/QuotaBar/releases/tag/v0.4.0",
                  "draft": \(key == "draft"),
                  "prerelease": \(key == "prerelease")
                }
                """.utf8
            )

            XCTAssertThrowsError(try GitHubReleaseParser.parse(data: data)) { error in
                XCTAssertEqual(
                    error as? GitHubReleaseParser.ParseError,
                    .unpublishedRelease
                )
            }
        }
    }
}
