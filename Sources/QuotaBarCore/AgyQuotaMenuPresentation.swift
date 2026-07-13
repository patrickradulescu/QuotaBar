public enum AgyQuotaUsageDetail {
    public static let setUpFromMenu = "Set up AGY quota from the menu"
    public static let openToRefresh = "Open AGY to refresh quota"
    public static let stale = "AGY quota is stale — open AGY to refresh"
}

public struct AgyQuotaMenuPresentation: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case checking
        case needsSetup
        case connected
        case needsRefresh
    }

    public let state: State

    public init(usage: ProviderUsage?) {
        guard let usage else {
            state = .checking
            return
        }

        switch usage.state {
        case .loading:
            state = .checking
        case .live:
            state = .connected
        case .actionRequired
            where usage.detail == AgyQuotaUsageDetail.openToRefresh
                || usage.detail == AgyQuotaUsageDetail.stale:
            state = .needsRefresh
        case .actionRequired, .unavailable, .error:
            state = .needsSetup
        }
    }

    public var statusTitle: String? {
        switch state {
        case .checking:
            return "AGY Quota: Checking…"
        case .connected:
            return "AGY Quota: Connected ✓"
        case .needsRefresh:
            return "AGY Quota: Open AGY to Refresh"
        case .needsSetup:
            return nil
        }
    }

    public var actionTitle: String? {
        switch state {
        case .checking:
            return nil
        case .needsSetup:
            return "Set Up AGY Quota…"
        case .connected, .needsRefresh:
            return "Reconnect AGY Quota…"
        }
    }
}
