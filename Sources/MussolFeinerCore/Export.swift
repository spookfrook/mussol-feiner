import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case json
    case csv
    case markdown

    public var id: String { rawValue }
    public var fileExtension: String { rawValue == "markdown" ? "md" : rawValue }

    public var label: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        case .markdown: return "Markdown"
        }
    }
}

public enum ExportScope: Equatable, Sendable {
    case all
    case range(DateInterval)
}

public enum DataExporter {
    public static func data(
        for entries: [TimeEntry],
        format: ExportFormat,
        scope: ExportScope = .all
    ) throws -> Data {
        let selectedEntries = selected(entries, scope: scope)

        switch format {
        case .json:
            return try jsonData(for: selectedEntries)
        case .csv:
            return Data(csvString(for: selectedEntries).utf8)
        case .markdown:
            return Data(markdownString(for: selectedEntries).utf8)
        }
    }

    public static func string(
        for entries: [TimeEntry],
        format: ExportFormat,
        scope: ExportScope = .all
    ) throws -> String {
        let exportedData = try data(for: entries, format: format, scope: scope)
        guard let value = String(data: exportedData, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return value
    }

    /// Writes an export atomically and applies owner-only permissions where supported.
    public static func write(
        entries: [TimeEntry],
        format: ExportFormat,
        scope: ExportScope = .all,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let exportData = try data(for: entries, format: format, scope: scope)
        let directoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try exportData.write(to: destinationURL, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: destinationURL.path
        )
    }

    /// Decodes a JSON export so the all-data export can serve as a portable backup.
    public static func decodeJSON(_ data: Data) throws -> [TimeEntry] {
        try exportDecoder.decode([TimeEntry].self, from: data)
    }

    public static func selected(
        _ entries: [TimeEntry],
        scope: ExportScope
    ) -> [TimeEntry] {
        let filtered: [TimeEntry]
        switch scope {
        case .all:
            filtered = entries
        case let .range(interval):
            filtered = entries.compactMap { entry in
                if entry.duration == 0 {
                    return entry.start >= interval.start && entry.start < interval.end ? entry : nil
                }
                guard AnalyticsEngine.overlappingDuration(of: entry, with: interval) > 0 else {
                    return nil
                }

                // A current-view export represents exactly that view. Clipping entries at
                // its boundaries keeps exported durations aligned with day/week analytics.
                return try? TimeEntry(
                    id: entry.id,
                    projectCode: entry.projectCode,
                    workMode: entry.workMode,
                    start: max(entry.start, interval.start),
                    end: min(entry.end, interval.end),
                    focusScore: entry.focusScore
                )
            }
        }

        return filtered.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") ||
                value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func markdownEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
    }

    private static func jsonData(for entries: [TimeEntry]) throws -> Data {
        try exportEncoder.encode(entries)
    }

    private static func csvString(for entries: [TimeEntry]) -> String {
        var rows = [
            "id,project_code,work_mode,work_mode_code,start,end,duration_seconds,focus_score"
        ]

        rows += entries.map { entry in
            let focus = entry.focusScore.map(String.init) ?? ""
            let fields = [
                entry.id.uuidString,
                entry.projectCode,
                entry.workMode.label,
                entry.workMode.code,
                iso8601String(from: entry.start),
                iso8601String(from: entry.end),
                secondsString(entry.duration),
                focus
            ]
            return fields.map(csvEscape).joined(separator: ",")
        }

        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private static func markdownString(for entries: [TimeEntry]) -> String {
        var rows = [
            "# Mussol Feiner Time Export",
            "",
            "| Project | Work mode | Start | End | Duration | Focus |",
            "|:--|:--|:--|:--|--:|--:|"
        ]

        rows += entries.map { entry in
            let values = [
                entry.projectCode,
                entry.workMode.label,
                iso8601String(from: entry.start),
                iso8601String(from: entry.end),
                clockString(entry.duration),
                entry.focusScore.map(String.init) ?? ""
            ].map(markdownEscape)
            return "| \(values.joined(separator: " | ")) |"
        }

        rows.append("")
        return rows.joined(separator: "\n")
    }

    private static func iso8601String(from date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static func secondsString(_ duration: TimeInterval) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), duration)
    }

    private static func clockString(_ duration: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(duration.rounded()))
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let seconds = wholeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let exportEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let exportDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = iso8601Formatter.date(from: string) ?? basicISO8601Formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(string)"
            )
        }
        return decoder
    }()

    private static let basicISO8601Formatter = ISO8601DateFormatter()
}
