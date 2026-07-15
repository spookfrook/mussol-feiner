import Foundation

/// Parses human elapsed-time input for backdating or correcting timers.
///
/// Accepted forms:
/// - Bare number, read as minutes: "45" is 45 minutes.
/// - Unit tokens in descending magnitude: "45m", "1.5h", "1h 30m", "2h 15m 10s".
///   A bare trailing number drops one level: "1h30" is 1h 30m, "10m 30" is 10m 30s.
/// - Clock notation: "1:30" is hours:minutes, "01:30:00" is hours:minutes:seconds.
public enum ElapsedTimeParser {
    /// Upper bound for accepted input; anything past a full day is assumed to be a typo.
    public static let maximumInterval: TimeInterval = 24 * 60 * 60

    public static func parse(_ input: String) -> TimeInterval? {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard !trimmed.isEmpty else { return nil }

        let interval = trimmed.contains(":") ? parseClock(trimmed) : parseUnits(trimmed)
        guard let interval, interval >= 0, interval <= maximumInterval else { return nil }
        return interval
    }

    // MARK: - Clock notation

    private static func parseClock(_ input: String) -> TimeInterval? {
        let parts = input.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part) else {
                return nil
            }
            values.append(value)
        }

        let hours = values[0]
        let minutes = values[1]
        let seconds = values.count == 3 ? values[2] : 0
        guard minutes < 60, seconds < 60 else { return nil }
        return TimeInterval(hours * 3_600 + minutes * 60 + seconds)
    }

    // MARK: - Unit notation

    private enum Unit: Int {
        case hours
        case minutes
        case seconds

        var secondsMultiplier: Double {
            switch self {
            case .hours: return 3_600
            case .minutes: return 60
            case .seconds: return 1
            }
        }
    }

    private struct Token {
        let value: Double
        let unit: Unit?
    }

    private static func parseUnits(_ input: String) -> TimeInterval? {
        guard let tokens = tokenize(input), !tokens.isEmpty else { return nil }

        // A single bare number means minutes: "45" is 45 minutes.
        if tokens.count == 1, tokens[0].unit == nil {
            return tokens[0].value * 60
        }

        var total: Double = 0
        var previousUnit: Unit?
        for token in tokens {
            let unit: Unit
            if let explicit = token.unit {
                unit = explicit
            } else if let previous = previousUnit, let implied = Unit(rawValue: previous.rawValue + 1) {
                // A bare number after a unit drops one level: "1h 30" is 30 minutes.
                unit = implied
            } else {
                return nil
            }
            if let previous = previousUnit, unit.rawValue <= previous.rawValue { return nil }
            total += token.value * unit.secondsMultiplier
            previousUnit = unit
        }
        return total
    }

    private static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        var index = input.startIndex

        while index < input.endIndex {
            if input[index].isWhitespace {
                index = input.index(after: index)
                continue
            }

            var digits = ""
            var sawSeparator = false
            while index < input.endIndex {
                let character = input[index]
                if character.isASCII && character.isNumber {
                    digits.append(character)
                } else if character == "." || character == ",", !sawSeparator, !digits.isEmpty {
                    sawSeparator = true
                    digits.append(".")
                } else {
                    break
                }
                index = input.index(after: index)
            }
            guard !digits.isEmpty, digits.last != ".", let value = Double(digits) else { return nil }

            // The unit may be separated from its number by whitespace: "45 min".
            var lookahead = index
            while lookahead < input.endIndex, input[lookahead].isWhitespace {
                lookahead = input.index(after: lookahead)
            }
            var letters = ""
            var lettersEnd = lookahead
            while lettersEnd < input.endIndex, input[lettersEnd].isLetter {
                letters.append(input[lettersEnd])
                lettersEnd = input.index(after: lettersEnd)
            }

            if letters.isEmpty {
                tokens.append(Token(value: value, unit: nil))
            } else if let unit = unit(named: letters) {
                tokens.append(Token(value: value, unit: unit))
                index = lettersEnd
            } else {
                return nil
            }
        }
        return tokens
    }

    private static func unit(named raw: String) -> Unit? {
        switch raw {
        case "h", "hr", "hrs", "hour", "hours": return .hours
        case "m", "min", "mins", "minute", "minutes": return .minutes
        case "s", "sec", "secs", "second", "seconds": return .seconds
        default: return nil
        }
    }
}
