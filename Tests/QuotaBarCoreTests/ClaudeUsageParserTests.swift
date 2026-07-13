import Foundation
import XCTest
@testable import QuotaBarCore

final class ClaudeUsageParserTests: XCTestCase {
    func testTerminalScreenAppliesCursorAddressingAndErase() {
        let screen = ANSIScreen(columns: 30, rows: 5)
        screen.feed(Data("Hello\u{1B}[2;4HWorld\u{1B}[2K\u{1B}[3;1HQuota 12% used".utf8))

        XCTAssertTrue(screen.renderedText.contains("Hello"))
        XCTAssertTrue(screen.renderedText.contains("Quota 12% used"))
        XCTAssertFalse(screen.renderedText.contains("World"))
    }

    func testParsesClaudeSessionAndWeeklyUsage() throws {
        let screen = """
        Usage
        Current session
          3% used
          Resets 9:10pm (Asia/Bangkok)
        Current week (all models)
          12% used
          Resets Jul 17 at 9pm (Asia/Bangkok)
        Current week (Fable)
          25% used
        """
        let observed = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-13T11:00:00Z")
        )
        let usage = try ClaudeUsageParser.parse(screen: screen, observedAt: observed)

        XCTAssertEqual(usage.provider, .claude)
        XCTAssertEqual(usage.primary?.usedPercent, 3)
        XCTAssertEqual(usage.secondary?.usedPercent, 12)
        XCTAssertEqual(usage.primary?.windowMinutes, 300)
        XCTAssertEqual(usage.secondary?.windowMinutes, 10_080)
    }
}
