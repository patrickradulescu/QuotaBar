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
        XCTAssertEqual(usage.namedWeeklyLimits?.first?.label, "Fable")
        XCTAssertEqual(usage.namedWeeklyLimits?.first?.window.usedPercent, 25)
        XCTAssertEqual(usage.namedWeeklyLimits?.first?.window.windowMinutes, 10_080)
    }

    func testParsesNewClaudeUsageLayoutAndRelativeResets() throws {
        let screen = """
        Your usage limits
        Current session  3% used
        Resets in 1 hr 26 min (Asia/Bangkok)
        Weekly limits
        All models  13% used
        Resets Fri 9:00 PM (Asia/Bangkok)
        Fable  25% used
        Resets Fri 9:00 PM (Asia/Bangkok)
        """
        let observed = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-13T12:00:00Z")
        )
        let usage = try ClaudeUsageParser.parse(screen: screen, observedAt: observed)

        XCTAssertEqual(usage.primary?.usedPercent, 3)
        XCTAssertEqual(usage.secondary?.usedPercent, 13)
        XCTAssertEqual(usage.namedWeeklyLimits?.first?.label, "Fable")
        XCTAssertEqual(usage.namedWeeklyLimits?.first?.window.usedPercent, 25)
        XCTAssertEqual(
            usage.primary?.resetsAt,
            ISO8601DateFormatter().date(from: "2026-07-13T13:26:00Z")
        )
        XCTAssertEqual(
            usage.secondary?.resetsAt,
            ISO8601DateFormatter().date(from: "2026-07-17T14:00:00Z")
        )
        XCTAssertEqual(
            usage.namedWeeklyLimits?.first?.window.resetsAt,
            ISO8601DateFormatter().date(from: "2026-07-17T14:00:00Z")
        )
    }
}
