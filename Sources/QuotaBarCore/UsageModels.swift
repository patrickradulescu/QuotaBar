import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case gemini

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        }
    }
}

public enum ProviderState: String, Codable, Sendable {
    case loading
    case live
    case actionRequired
    case unavailable
    case error
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

public struct NamedUsageWindow: Codable, Equatable, Sendable {
    public let label: String
    public let window: UsageWindow

    public init(label: String, window: UsageWindow) {
        self.label = label
        self.window = window
    }
}

public struct ProviderUsage: Codable, Equatable, Sendable {
    public let provider: ProviderKind
    public let state: ProviderState
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let namedWeeklyLimits: [NamedUsageWindow]?
    public let observedAt: Date
    public let detail: String?

    public init(
        provider: ProviderKind,
        state: ProviderState,
        primary: UsageWindow? = nil,
        secondary: UsageWindow? = nil,
        namedWeeklyLimits: [NamedUsageWindow]? = nil,
        observedAt: Date = Date(),
        detail: String? = nil
    ) {
        self.provider = provider
        self.state = state
        self.primary = primary
        self.secondary = secondary
        self.namedWeeklyLimits = namedWeeklyLimits
        self.observedAt = observedAt
        self.detail = detail
    }

    public static func loading(_ provider: ProviderKind) -> ProviderUsage {
        ProviderUsage(provider: provider, state: .loading)
    }

    public static func unavailable(_ provider: ProviderKind, detail: String) -> ProviderUsage {
        ProviderUsage(provider: provider, state: .unavailable, detail: detail)
    }

    public static func actionRequired(_ provider: ProviderKind, detail: String) -> ProviderUsage {
        ProviderUsage(provider: provider, state: .actionRequired, detail: detail)
    }

    public static func failed(_ provider: ProviderKind, detail: String) -> ProviderUsage {
        ProviderUsage(provider: provider, state: .error, detail: detail)
    }
}

public extension UsageWindow {
    var compactWindowLabel: String {
        if windowMinutes % 10_080 == 0 {
            return "\(windowMinutes / 10_080)w"
        }
        if windowMinutes % 1_440 == 0 {
            return "\(windowMinutes / 1_440)d"
        }
        if windowMinutes % 60 == 0 {
            return "\(windowMinutes / 60)h"
        }
        return "\(windowMinutes)m"
    }
}
