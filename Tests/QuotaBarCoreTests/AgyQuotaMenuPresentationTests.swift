import XCTest
@testable import QuotaBarCore

final class AgyQuotaMenuPresentationTests: XCTestCase {
    func testChecksBeforeUsageArrives() {
        let presentation = AgyQuotaMenuPresentation(usage: nil)

        XCTAssertEqual(presentation.state, .checking)
        XCTAssertEqual(presentation.statusTitle, "AGY Quota: Checking…")
        XCTAssertNil(presentation.actionTitle)
    }

    func testShowsConnectedStatusAndReconnectActionForLiveUsage() {
        let presentation = AgyQuotaMenuPresentation(usage: ProviderUsage(
            provider: .gemini,
            state: .live
        ))

        XCTAssertEqual(presentation.state, .connected)
        XCTAssertEqual(presentation.statusTitle, "AGY Quota: Connected ✓")
        XCTAssertEqual(presentation.actionTitle, "Reconnect AGY Quota…")
    }

    func testShowsRefreshGuidanceForStaleCacheDetails() {
        for detail in [
            AgyQuotaUsageDetail.openToRefresh,
            AgyQuotaUsageDetail.stale
        ] {
            let presentation = AgyQuotaMenuPresentation(usage: .actionRequired(
                .gemini,
                detail: detail
            ))

            XCTAssertEqual(presentation.state, .needsRefresh)
            XCTAssertEqual(
                presentation.statusTitle,
                "AGY Quota: Open AGY to Refresh"
            )
            XCTAssertEqual(presentation.actionTitle, "Reconnect AGY Quota…")
        }
    }

    func testOffersSetupWhenNoQuotaHasBeenReceived() {
        let presentation = AgyQuotaMenuPresentation(usage: .actionRequired(
            .gemini,
            detail: AgyQuotaUsageDetail.setUpFromMenu
        ))

        XCTAssertEqual(presentation.state, .needsSetup)
        XCTAssertNil(presentation.statusTitle)
        XCTAssertEqual(presentation.actionTitle, "Set Up AGY Quota…")
    }
}
