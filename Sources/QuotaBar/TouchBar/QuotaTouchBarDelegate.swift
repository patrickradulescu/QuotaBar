import AppKit
import QuotaBarCore

final class QuotaTouchBarDelegate: NSObject, NSTouchBarDelegate {
    private static let dashboardIdentifier = NSTouchBarItem.Identifier(
        "com.patrickradulescu.QuotaBar.dashboard"
    )

    private var dashboardView: QuotaBarTouchView?
    private var latestSnapshots: [ProviderKind: ProviderUsage] = [:]

    func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [Self.dashboardIdentifier]
        touchBar.principalItemIdentifier = Self.dashboardIdentifier
        return touchBar
    }

    func update(_ snapshots: [ProviderKind: ProviderUsage]) {
        latestSnapshots = snapshots
        dashboardView?.update(snapshots)
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == Self.dashboardIdentifier else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        let view = QuotaBarTouchView()
        view.update(latestSnapshots)
        item.view = view
        item.customizationLabel = "QuotaBar Usage"
        dashboardView = view
        return item
    }
}
