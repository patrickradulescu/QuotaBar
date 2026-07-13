import Foundation

public enum ClaudeUsageParser {
    public enum ParseError: Error, Equatable {
        case missingSessionUsage
    }

    public static func parse(screen: String, observedAt: Date = Date()) throws -> ProviderUsage {
        let lines = screen
            .components(separatedBy: .newlines)
            .map(normalizeWhitespace)

        guard let sessionIndex = lines.firstIndex(where: {
            $0.localizedCaseInsensitiveContains("Current session")
        }), let sessionPercent = percent(after: sessionIndex, in: lines) else {
            throw ParseError.missingSessionUsage
        }

        let weekIndex = lines.indices.first(where: { isAllModelsHeading(lines[$0]) })

        let primaryReset = resetDate(after: sessionIndex, in: lines, now: observedAt)
        let secondaryPercent = weekIndex.flatMap { percent(after: $0, in: lines) }
        let secondaryReset = weekIndex.flatMap { resetDate(after: $0, in: lines, now: observedAt) }
        let namedWeeklyLimits = namedWeeklyLimits(in: lines, now: observedAt)

        return ProviderUsage(
            provider: .claude,
            state: .live,
            primary: UsageWindow(
                usedPercent: sessionPercent,
                windowMinutes: 300,
                resetsAt: primaryReset
            ),
            secondary: secondaryPercent.map {
                UsageWindow(usedPercent: $0, windowMinutes: 10_080, resetsAt: secondaryReset)
            },
            namedWeeklyLimits: namedWeeklyLimits.isEmpty ? nil : namedWeeklyLimits,
            observedAt: observedAt
        )
    }

    private static func isAllModelsHeading(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        if lowercased == "all models" || lowercased.hasPrefix("all models ") {
            return true
        }
        guard lowercased.contains("current week") else { return false }
        return !["fable", "opus", "sonnet"].contains(where: lowercased.contains)
    }

    private static func namedWeeklyLimits(in lines: [String], now: Date) -> [NamedUsageWindow] {
        var limits: [NamedUsageWindow] = []
        var seenLabels: Set<String> = []

        for index in lines.indices {
            guard let label = modelLabel(from: lines[index]),
                  seenLabels.insert(label.lowercased()).inserted,
                  let usedPercent = percent(after: index, in: lines) else {
                continue
            }

            limits.append(NamedUsageWindow(
                label: label,
                window: UsageWindow(
                    usedPercent: usedPercent,
                    windowMinutes: 10_080,
                    resetsAt: resetDate(after: index, in: lines, now: now)
                )
            ))
        }
        return limits
    }

    private static func modelLabel(from line: String) -> String? {
        let knownLabels = ["Fable", "Opus", "Sonnet"]
        let lowercased = line.lowercased()
        if let exact = knownLabels.first(where: {
            lowercased == $0.lowercased() || lowercased.hasPrefix("\($0.lowercased()) ")
        }) {
            return exact
        }

        guard let parenthesized = firstMatch(#"current week\s*\(([^)]+)\)"#, in: line),
              parenthesized.caseInsensitiveCompare("all models") != .orderedSame else {
            return nil
        }
        return knownLabels.first(where: {
            parenthesized.localizedCaseInsensitiveContains($0)
        })
    }

    private static func percent(after index: Int, in lines: [String]) -> Double? {
        let upper = min(lines.endIndex, index + 6)
        for line in lines[index..<upper] {
            guard let match = firstMatch(#"([0-9]+(?:\.[0-9]+)?)%\s*used"#, in: line),
                  let value = Double(match) else {
                continue
            }
            return value
        }
        return nil
    }

    private static func resetDate(after index: Int, in lines: [String], now: Date) -> Date? {
        let upper = min(lines.endIndex, index + 7)
        guard let resetLine = lines[index..<upper].first(where: {
            $0.localizedCaseInsensitiveContains("Resets ")
        }) else {
            return nil
        }

        return parseResetLine(resetLine, now: now)
    }

    private static func parseResetLine(_ line: String, now: Date) -> Date? {
        var value = line
        if let range = value.range(of: "Resets ", options: .caseInsensitive) {
            value = String(value[range.upperBound...])
        }

        var timeZone = TimeZone.current
        if let zone = firstMatch(#"\(([^)]+)\)$"#, in: value),
           let parsedZone = TimeZone(identifier: zone) {
            timeZone = parsedZone
            value = value.replacingOccurrences(of: "(\(zone))", with: "")
        }
        value = normalizeWhitespace(value)

        if let relative = relativeResetDate(value, now: now) {
            return relative
        }

        let locale = Locale(identifier: "en_US_POSIX")
        if value.range(of: #"[A-Za-z]{3}\s+[0-9]{1,2}\s+at"#, options: .regularExpression) != nil {
            let calendar = Calendar(identifier: .gregorian)
            let year = calendar.component(.year, from: now)
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = "MMM d 'at' h:mma yyyy"
            guard var date = formatter.date(from: "\(compactMeridiem(value)) \(year)") else {
                return nil
            }
            if date < now.addingTimeInterval(-86_400),
               let nextYear = Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: date) {
                date = nextYear
            }
            return date
        }

        if let weekday = weekdayResetDate(value, now: now, timeZone: timeZone) {
            return weekday
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mma"
        guard let parsed = formatter.date(from: compactMeridiem(value)) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = calendar.dateComponents([.hour, .minute], from: parsed)
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        guard var result = calendar.date(from: components) else { return nil }
        if result <= now {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
        }
        return result
    }

    private static func relativeResetDate(_ value: String, now: Date) -> Date? {
        guard value.lowercased().hasPrefix("in ") else { return nil }

        let days = firstMatch(#"([0-9]+)\s*(?:d|day|days)\b"#, in: value).flatMap(Int.init) ?? 0
        let hours = firstMatch(#"([0-9]+)\s*(?:h|hr|hrs|hour|hours)\b"#, in: value).flatMap(Int.init) ?? 0
        let minutes = firstMatch(#"([0-9]+)\s*(?:m|min|mins|minute|minutes)\b"#, in: value).flatMap(Int.init) ?? 0
        guard days + hours + minutes > 0 else { return nil }

        return Calendar(identifier: .gregorian).date(
            byAdding: DateComponents(day: days, hour: hours, minute: minutes),
            to: now
        )
    }

    private static func weekdayResetDate(
        _ value: String,
        now: Date,
        timeZone: TimeZone
    ) -> Date? {
        guard let weekdayName = firstMatch(
            #"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b"#,
            in: value
        ), let clock = firstMatch(
            #"^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(.+)$"#,
            in: value
        ) else {
            return nil
        }

        let weekdays = [
            "sun": 1, "mon": 2, "tue": 3, "wed": 4,
            "thu": 5, "fri": 6, "sat": 7
        ]
        guard let weekday = weekdays[weekdayName.lowercased()],
              let time = parseClock(clock, timeZone: timeZone) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let clockComponents = calendar.dateComponents([.hour, .minute], from: time)
        var target = DateComponents()
        target.calendar = calendar
        target.timeZone = timeZone
        target.weekday = weekday
        target.hour = clockComponents.hour
        target.minute = clockComponents.minute
        return calendar.nextDate(
            after: now,
            matching: target,
            matchingPolicy: .nextTime,
            direction: .forward
        )
    }

    private static func parseClock(_ value: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["h:mm a", "h:mma", "h a", "ha"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func normalizeWhitespace(_ string: String) -> String {
        string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compactMeridiem(_ string: String) -> String {
        string.replacingOccurrences(
            of: #"\s+(am|pm)$"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func firstMatch(_ pattern: String, in string: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                  in: string,
                  range: NSRange(string.startIndex..., in: string)
              ), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[range])
    }
}
