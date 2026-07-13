import Foundation

public struct AgyQuotaBucket: Codable, Equatable, Sendable {
    public let remainingFraction: Double
    public let resetsAt: Date?

    public init(remainingFraction: Double, resetsAt: Date?) {
        self.remainingFraction = remainingFraction
        self.resetsAt = resetsAt
    }
}

/// The complete on-disk AGY cache. It intentionally contains only normalized
/// quota values and never the raw statusline payload, account, workspace,
/// conversation, model prompt, or filesystem paths supplied by AGY.
public struct AgyQuotaSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let observedAt: Date
    public let sourceVersion: String?
    public let fiveHour: AgyQuotaBucket?
    public let weekly: AgyQuotaBucket?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        observedAt: Date,
        sourceVersion: String?,
        fiveHour: AgyQuotaBucket?,
        weekly: AgyQuotaBucket?
    ) {
        self.schemaVersion = schemaVersion
        self.observedAt = observedAt
        self.sourceVersion = sourceVersion
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    public func normalizedUsage(
        now: Date = Date(),
        maximumAge: TimeInterval = 30 * 60
    ) -> ProviderUsage? {
        guard schemaVersion == Self.currentSchemaVersion,
              observedAt <= now.addingTimeInterval(5 * 60),
              now.timeIntervalSince(observedAt) <= maximumAge else {
            return nil
        }

        let validFiveHour = validBucket(fiveHour, now: now)
        let validWeekly = validBucket(weekly, now: now)
        guard validFiveHour != nil || validWeekly != nil else { return nil }

        let fiveHourWindow = validFiveHour.map {
            UsageWindow(
                usedPercent: (1 - $0.remainingFraction) * 100,
                windowMinutes: 300,
                resetsAt: $0.resetsAt
            )
        }
        let weeklyWindow = validWeekly.map {
            UsageWindow(
                usedPercent: (1 - $0.remainingFraction) * 100,
                windowMinutes: 10_080,
                resetsAt: $0.resetsAt
            )
        }

        return ProviderUsage(
            provider: .gemini,
            state: .live,
            primary: fiveHourWindow ?? weeklyWindow,
            secondary: fiveHourWindow == nil ? nil : weeklyWindow,
            observedAt: observedAt,
            detail: "AGY statusline"
        )
    }

    public var compactStatusLine: String {
        var parts = ["QuotaBar · Gemini"]
        if let fiveHour,
           fiveHour.remainingFraction.isFinite,
           (0...1).contains(fiveHour.remainingFraction) {
            parts.append("5H \(Self.percent(fiveHour.remainingFraction))% LEFT")
        }
        if let weekly,
           weekly.remainingFraction.isFinite,
           (0...1).contains(weekly.remainingFraction) {
            parts.append("WK \(Self.percent(weekly.remainingFraction))% LEFT")
        }
        return parts.joined(separator: " · ")
    }

    private func validBucket(_ bucket: AgyQuotaBucket?, now: Date) -> AgyQuotaBucket? {
        guard let bucket,
              bucket.remainingFraction.isFinite,
              (0...1).contains(bucket.remainingFraction),
              bucket.resetsAt.map({ $0 > now }) ?? true else {
            return nil
        }
        return bucket
    }

    private static func percent(_ fraction: Double) -> String {
        let value = min(max(fraction * 100, 0), 100)
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}

public enum AgyStatusPayloadParser {
    public enum ParseError: Error, Equatable {
        case malformedPayload
        case invalidQuota
    }

    private struct Payload: Decodable {
        let version: String?
        let quota: [String: RawBucket]?
    }

    private struct RawBucket: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let resetInSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case remainingFraction = "remaining_fraction"
            case resetTime = "reset_time"
            case resetInSeconds = "reset_in_seconds"
        }
    }

    /// Returns `nil` for AGY's expected startup events where `quota` is null or
    /// absent. Callers should retain the last good cache in that case.
    public static func parse(
        data: Data,
        observedAt: Date = Date()
    ) throws -> AgyQuotaSnapshot? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ParseError.malformedPayload
        }
        guard let quota = payload.quota else { return nil }

        let fiveHour = normalizedBucket(quota["gemini-5h"], observedAt: observedAt)
        let weekly = normalizedBucket(quota["gemini-weekly"], observedAt: observedAt)
        guard fiveHour != nil || weekly != nil else {
            throw ParseError.invalidQuota
        }

        return AgyQuotaSnapshot(
            observedAt: observedAt,
            sourceVersion: sanitizedVersion(payload.version),
            fiveHour: fiveHour,
            weekly: weekly
        )
    }

    private static func normalizedBucket(
        _ raw: RawBucket?,
        observedAt: Date
    ) -> AgyQuotaBucket? {
        guard let raw,
              let fraction = raw.remainingFraction,
              fraction.isFinite,
              (0...1).contains(fraction) else {
            return nil
        }

        let maximumReset = observedAt.addingTimeInterval(366 * 24 * 60 * 60)
        let resetFromTimestamp = raw.resetTime
            .flatMap(parseISO8601)
            .flatMap { reset -> Date? in
                guard reset > observedAt, reset <= maximumReset else { return nil }
                return reset
            }
        let resetFromDuration = raw.resetInSeconds.flatMap { seconds -> Date? in
            guard seconds > 0, seconds <= 366 * 24 * 60 * 60 else { return nil }
            return observedAt.addingTimeInterval(TimeInterval(seconds))
        }
        return AgyQuotaBucket(
            remainingFraction: fraction,
            resetsAt: resetFromTimestamp ?? resetFromDuration
        )
    }

    private static func parseISO8601(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func sanitizedVersion(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.count <= 32,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || byte == 46 || byte == 45
              }) else {
            return nil
        }
        return value
    }
}

public enum AgyQuotaCacheCodec {
    public static func encode(_ snapshot: AgyQuotaSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> AgyQuotaSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgyQuotaSnapshot.self, from: data)
    }
}

public enum AgyQuotaCachePolicy {
    public static let unchangedWriteThrottle: TimeInterval = 15

    /// Changed quota is persisted immediately. Identical callbacks are
    /// coalesced briefly to avoid statusline write amplification, but are
    /// eventually persisted so a running AGY remains fresh.
    public static func shouldPersist(
        incoming: AgyQuotaSnapshot,
        replacing existing: AgyQuotaSnapshot,
        unchangedWriteThrottle: TimeInterval = unchangedWriteThrottle
    ) -> Bool {
        guard quotaIsEquivalent(incoming, existing) else { return true }
        let elapsed = incoming.observedAt.timeIntervalSince(existing.observedAt)
        guard elapsed >= 0 else { return true }
        return elapsed >= unchangedWriteThrottle
    }

    private static func quotaIsEquivalent(
        _ lhs: AgyQuotaSnapshot,
        _ rhs: AgyQuotaSnapshot
    ) -> Bool {
        lhs.schemaVersion == AgyQuotaSnapshot.currentSchemaVersion
            && rhs.schemaVersion == AgyQuotaSnapshot.currentSchemaVersion
            && lhs.sourceVersion == rhs.sourceVersion
            && rhs.observedAt <= lhs.observedAt.addingTimeInterval(5 * 60)
            && bucketIsEquivalent(lhs.fiveHour, rhs.fiveHour)
            && bucketIsEquivalent(lhs.weekly, rhs.weekly)
    }

    private static func bucketIsEquivalent(
        _ lhs: AgyQuotaBucket?,
        _ rhs: AgyQuotaBucket?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            guard abs(lhs.remainingFraction - rhs.remainingFraction)
                    < 0.000_000_001 else {
                return false
            }
            switch (lhs.resetsAt, rhs.resetsAt) {
            case (nil, nil):
                return true
            case let (lhsReset?, rhsReset?):
                return abs(lhsReset.timeIntervalSince(rhsReset)) <= 5
            default:
                return false
            }
        default:
            return false
        }
    }
}
