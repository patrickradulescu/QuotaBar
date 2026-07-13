import AppKit
import ObjectiveC.runtime

/// A deliberately tiny seam around the one private API QuotaBar needs.
///
/// Public NSTouchBar APIs only render while the owning app is active. QuotaBar is a
/// menu-bar agent, so it uses the system-modal presenter that macOS itself still
/// ships on Touch Bar Macs. No DFR private framework is loaded and no Control Strip
/// item is installed.
enum PrivateTouchBarBridge {
    private static let presentSelector = NSSelectorFromString(
        "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"
    )
    private static let dismissSelector = NSSelectorFromString("dismissSystemModalTouchBar:")

    private static let expectedPresentEncoding = "v40@0:8@16q24@32"
    private static let expectedDismissEncoding = "v24@0:8@16"

    static var isSupported: Bool {
        guard let presentMethod = class_getClassMethod(NSTouchBar.self, presentSelector),
              let dismissMethod = class_getClassMethod(NSTouchBar.self, dismissSelector),
              method_getNumberOfArguments(presentMethod) == 5,
              method_getNumberOfArguments(dismissMethod) == 3,
              let presentEncoding = method_getTypeEncoding(presentMethod),
              let dismissEncoding = method_getTypeEncoding(dismissMethod) else {
            return false
        }

        return String(cString: presentEncoding) == expectedPresentEncoding &&
            String(cString: dismissEncoding) == expectedDismissEncoding
    }

    @discardableResult
    static func present(_ touchBar: NSTouchBar) -> Bool {
        guard isSupported,
              let method = class_getClassMethod(NSTouchBar.self, presentSelector) else {
            return false
        }

        typealias PresentImplementation = @convention(c) (
            AnyClass,
            Selector,
            NSTouchBar,
            Int64,
            NSString?
        ) -> Void

        let implementation = unsafeBitCast(
            method_getImplementation(method),
            to: PresentImplementation.self
        )
        implementation(
            NSTouchBar.self,
            presentSelector,
            touchBar,
            1,
            nil
        )
        return true
    }

    static func dismiss(_ touchBar: NSTouchBar) {
        guard isSupported,
              let method = class_getClassMethod(NSTouchBar.self, dismissSelector) else {
            return
        }

        typealias DismissImplementation = @convention(c) (
            AnyClass,
            Selector,
            NSTouchBar
        ) -> Void

        let implementation = unsafeBitCast(
            method_getImplementation(method),
            to: DismissImplementation.self
        )
        implementation(NSTouchBar.self, dismissSelector, touchBar)
    }
}
