import Foundation
import XCTest
@testable import QuotaBarCore

final class GeminiUsageParserTests: XCTestCase {
    func testParsesProAndFlashRowsFromModelDialog() throws {
        let screen = """
        Select Model
        Model usage
        Pro          ▬▬▬▬▬  12%  Resets: 9:00 PM (4h 5m)
        Flash       ▬▬▬▬▬▬  34%  Resets: 10:30 PM (5h 35m)
        Flash Lite      ▬▬   8%  Resets: 8:15 PM (3h 20m)
        """
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let usage = try GeminiUsageParser.parse(screen: screen, observedAt: observedAt)

        XCTAssertEqual(usage.provider, .gemini)
        XCTAssertEqual(usage.state, .live)
        XCTAssertEqual(usage.primary?.usedPercent, 12)
        XCTAssertEqual(usage.secondary?.usedPercent, 34)
        XCTAssertEqual(usage.primary?.windowMinutes, 1_440)
        XCTAssertEqual(usage.secondary?.windowMinutes, 1_440)
        XCTAssertEqual(
            usage.primary?.resetsAt,
            observedAt.addingTimeInterval((4 * 60 + 5) * 60)
        )
        XCTAssertEqual(
            usage.secondary?.resetsAt,
            observedAt.addingTimeInterval((5 * 60 + 35) * 60)
        )
    }

    func testRequiresProRow() {
        XCTAssertThrowsError(
            try GeminiUsageParser.parse(screen: "Flash 4% Resets: 9:00 PM (2h)")
        ) { error in
            XCTAssertEqual(error as? GeminiUsageParser.ParseError, .missingProUsage)
        }
    }
}
