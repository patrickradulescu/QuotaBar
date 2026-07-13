import Foundation

public enum CodexRateLimitParser {
    public enum ParseError: Error, Equatable {
        case invalidResponse
        case serverError(String)
        case missingRateLimits
    }

    public static func parse(jsonLine: Data, observedAt: Date = Date()) throws -> ProviderUsage {
        let response = try JSONDecoder().decode(Response.self, from: jsonLine)

        if let error = response.error {
            throw ParseError.serverError(error.message)
        }

        guard let result = response.result else {
            throw ParseError.invalidResponse
        }

        let selected = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        guard let limits = selected, let primary = limits.primary else {
            throw ParseError.missingRateLimits
        }

        return ProviderUsage(
            provider: .codex,
            state: .live,
            primary: primary.usageWindow,
            secondary: limits.secondary?.usageWindow,
            observedAt: observedAt,
            detail: limits.planType
        )
    }
}

private extension CodexRateLimitParser {
    struct Response: Decodable {
        let result: ResultPayload?
        let error: ErrorPayload?
    }

    struct ErrorPayload: Decodable {
        let message: String
    }

    struct ResultPayload: Decodable {
        let rateLimits: RateLimits?
        let rateLimitsByLimitId: [String: RateLimits]?
    }

    struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int
        let resetsAt: TimeInterval?

        var usageWindow: UsageWindow {
            UsageWindow(
                usedPercent: usedPercent,
                windowMinutes: windowDurationMins,
                resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
            )
        }
    }
}
