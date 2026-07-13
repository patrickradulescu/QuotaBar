import Foundation
import XCTest
@testable import QuotaBarCore

final class CodexRateLimitParserTests: XCTestCase {
    func testParsesCodexBucketFromMultiBucketResponse() throws {
        let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":60,"resetsAt":1800000000}},"rateLimitsByLimitId":{"codex":{"planType":"pro","primary":{"usedPercent":6,"windowDurationMins":10080,"resetsAt":1784511014},"secondary":null}}}}"#

        let usage = try CodexRateLimitParser.parse(
            jsonLine: Data(json.utf8),
            observedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(usage.provider, .codex)
        XCTAssertEqual(usage.state, .live)
        XCTAssertEqual(usage.primary?.usedPercent, 6)
        XCTAssertEqual(usage.primary?.remainingPercent, 94)
        XCTAssertEqual(usage.primary?.windowMinutes, 10_080)
        XCTAssertEqual(usage.detail, "pro")
    }

    func testClampsUsagePercent() {
        let low = UsageWindow(usedPercent: -2, windowMinutes: 60, resetsAt: nil)
        let high = UsageWindow(usedPercent: 104, windowMinutes: 60, resetsAt: nil)

        XCTAssertEqual(low.usedPercent, 0)
        XCTAssertEqual(high.usedPercent, 100)
    }

    func testReportsServerError() {
        let json = #"{"id":2,"error":{"code":401,"message":"Login required"}}"#

        XCTAssertThrowsError(
            try CodexRateLimitParser.parse(jsonLine: Data(json.utf8))
        ) { error in
            XCTAssertEqual(
                error as? CodexRateLimitParser.ParseError,
                .serverError("Login required")
            )
        }
    }
}
