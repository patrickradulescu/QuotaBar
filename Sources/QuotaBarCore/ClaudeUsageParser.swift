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

        let weekIndex = lines.indices.first(where: { index in
            let line = lines[index].lowercased()
            guard line.contains("current week") else { return false }
            return !line.contains("fable") && !line.contains("opus") && !line.contains("sonnet")
        })

        let primaryReset = resetDate(after: sessionIndex, in: lines, now: observedAt)
        let secondaryPercent = weekIndex.flatMap { percent(after: $0, in: lines) }
        let secondaryReset = weekIndex.flatMap { resetDate(after: $0, in: lines, now: observedAt) }

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
            observedAt: observedAt
        )
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
