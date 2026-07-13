import Foundation

/// Parses only the visible, documented quota rows shown by Gemini CLI's
/// `/model` dialog. It does not consume credential files or API responses.
public enum GeminiUsageParser {
    public enum ParseError: Error, Equatable {
        case missingProUsage
    }

    private struct QuotaRow {
        let usedPercent: Double
        let resetsAt: Date?
    }

    public static func parse(screen: String, observedAt: Date = Date()) throws -> ProviderUsage {
        var pro: QuotaRow?
        var flash: QuotaRow?

        for rawLine in screen.components(separatedBy: .newlines) {
            let line = normalizeWhitespace(rawLine)
            guard let parsed = parseRow(line, observedAt: observedAt) else { continue }

            switch parsed.name.lowercased() {
            case "pro":
                pro = QuotaRow(usedPercent: parsed.usedPercent, resetsAt: parsed.resetsAt)
            case "flash":
                flash = QuotaRow(usedPercent: parsed.usedPercent, resetsAt: parsed.resetsAt)
            default:
                break
            }
        }

        guard let pro else {
            throw ParseError.missingProUsage
        }

        return ProviderUsage(
            provider: .gemini,
            state: .live,
            primary: UsageWindow(
                usedPercent: pro.usedPercent,
                windowMinutes: 1_440,
                resetsAt: pro.resetsAt
            ),
            secondary: flash.map {
                UsageWindow(
                    usedPercent: $0.usedPercent,
                    windowMinutes: 1_440,
                    resetsAt: $0.resetsAt
                )
            },
            observedAt: observedAt
        )
    }

    private static func parseRow(
        _ line: String,
        observedAt: Date
    ) -> (name: String, usedPercent: Double, resetsAt: Date?)? {
        let pattern = #"^(Pro|Flash)(?!\s+Lite\b)\b.*?([0-9]+(?:\.[0-9]+)?)%(?:\s+Resets:\s*(.+))?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(
                  in: line,
                  range: NSRange(line.startIndex..., in: line)
              ),
              let nameRange = Range(match.range(at: 1), in: line),
              let percentRange = Range(match.range(at: 2), in: line),
              let percent = Double(line[percentRange]) else {
            return nil
        }

        let resetText: String?
        if match.range(at: 3).location != NSNotFound,
           let range = Range(match.range(at: 3), in: line) {
            resetText = String(line[range])
        } else {
            resetText = nil
        }

        return (
            name: String(line[nameRange]),
            usedPercent: percent,
            resetsAt: resetText.flatMap { parseReset($0, observedAt: observedAt) }
        )
    }

    private static func parseReset(_ value: String, observedAt: Date) -> Date? {
        if let duration = durationSeconds(in: value) {
            return observedAt.addingTimeInterval(duration)
        }

        let time = value
            .replacingOccurrences(
                of: #"\s*\([^)]*\)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "h:mm a"
        guard let parsedTime = formatter.date(from: time) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let clock = calendar.dateComponents([.hour, .minute], from: parsedTime)
        let day = calendar.dateComponents([.year, .month, .day], from: observedAt)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = clock.hour
        components.minute = clock.minute

        guard var result = calendar.date(from: components) else { return nil }
        if result <= observedAt {
            result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
        }
        return result
    }

    private static func durationSeconds(in value: String) -> TimeInterval? {
        guard let expression = try? NSRegularExpression(
            pattern: #"\(\s*(?:(\d+)h)?\s*(?:(\d+)m)?\s*\)"#,
            options: [.caseInsensitive]
        ), let match = expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) else {
            return nil
        }

        let hours = integerCapture(1, match: match, in: value) ?? 0
        let minutes = integerCapture(2, match: match, in: value) ?? 0
        guard hours > 0 || minutes > 0 else { return nil }
        return TimeInterval((hours * 60 + minutes) * 60)
    }

    private static func integerCapture(
        _ index: Int,
        match: NSTextCheckingResult,
        in value: String
    ) -> Int? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: value) else {
            return nil
        }
        return Int(value[range])
    }

    private static func normalizeWhitespace(_ string: String) -> String {
        string.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
