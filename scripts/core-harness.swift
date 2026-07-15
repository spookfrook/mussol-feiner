import Foundation

enum HarnessFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case let .expectation(message): return message
        }
    }
}

@main
enum MussolFeinerCoreHarness {
    @MainActor
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MussolFeinerHarness-\(UUID().uuidString)", isDirectory: true)
        let storage = root.appendingPathComponent("time-tracking.json")
        defer { try? fileManager.removeItem(at: root) }

        let store = try TimeTrackingStore(storageURL: storage)
        let monday = isoDate("2026-07-13T09:00:00Z")

        try expect(store.entries.isEmpty, "Store should start empty")
        try expect(store.activeTimer == nil, "Store should start without an active timer")

        let firstSwitch = try store.startTimer(
            projectCode: "one",
            workMode: .deepWork,
            at: monday
        )
        try expect(firstSwitch == nil, "First start should not create a completed entry")

        let completedDeep = try store.startTimer(
            projectCode: "two",
            workMode: .activeMeeting,
            at: monday.addingTimeInterval(3_600)
        )
        try expect(completedDeep?.projectCode == "ONE", "Switch should complete the previous project")
        try expect(completedDeep?.duration == 3_600, "Switched entry should preserve its duration")

        let completedMeeting = try store.stopTimer(
            at: monday.addingTimeInterval(5_400),
            focusScore: 4
        )
        try expect(completedMeeting?.projectCode == "TWO", "Stop should complete the active timer")

        _ = try store.addEntry(
            projectCode: "tri",
            workMode: .shallowWork,
            start: monday.addingTimeInterval(5_400),
            end: monday.addingTimeInterval(7_200),
            focusScore: 2
        )

        let reloaded = try TimeTrackingStore(storageURL: storage)
        try expect(reloaded.entries.count == 3, "Reload should recover all completed entries")
        try expect(reloaded.activeTimer == nil, "Reload should preserve stopped timer state")

        let week = AnalyticsEngine.weekInterval(containing: monday)
        let summary = AnalyticsEngine.summary(entries: reloaded.entries, in: week)
        try expect(summary.totalDuration == 7_200, "Weekly total should include all overlapping time")
        try expect(summary.duration(for: .deepWork) == 3_600, "Deep Work total is incorrect")
        try expect(summary.meetingDuration == 1_800, "Meeting total is incorrect")
        try expect(abs((summary.averageFocusScore ?? 0) - 3.0) < 0.0001, "Focus must be duration-weighted")

        let mondayComponents = Calendar(identifier: .gregorian).dateComponents(
            [.weekday],
            from: week.start
        )
        try expect(mondayComponents.weekday == 2, "Week buckets must start on Monday")

        let json = try DataExporter.data(for: reloaded.entries, format: .json)
        let decoded = try DataExporter.decodeJSON(json)
        try expect(decoded.count == 3, "JSON export should round-trip")

        let csv = try DataExporter.string(for: reloaded.entries, format: .csv)
        try expect(csv.contains("Deep Work,DPW"), "CSV export is missing work-mode fields")
        try expect(csv.hasSuffix("\r\n"), "CSV export must use RFC 4180 line endings")
        let csvRows = csv.components(separatedBy: "\r\n")
        try expect(csvRows.count == 5, "CSV export must contain a header plus three rows")
        try expect(csvRows.last == "", "CSV export must end after its final line ending")
        try expect(
            csvRows.dropFirst().dropLast().contains(where: { $0.hasSuffix(",") }),
            "CSV export must leave a missing focus score blank"
        )

        let markdown = try DataExporter.string(for: reloaded.entries, format: .markdown)
        try expect(markdown.contains("| ONE | Deep Work |"), "Markdown export is missing entries")

        let directoryPermissions = try fileManager.attributesOfItem(
            atPath: storage.deletingLastPathComponent().path
        )[.posixPermissions] as? NSNumber
        let filePermissions = try fileManager.attributesOfItem(atPath: storage.path)[.posixPermissions] as? NSNumber
        try expect(directoryPermissions?.intValue == 0o700, "Storage directory must be owner-only")
        try expect(filePermissions?.intValue == 0o600, "Storage file must be owner-only")

        _ = try reloaded.startTimer(
            projectCode: "adj",
            workMode: .deepWork,
            at: monday.addingTimeInterval(10_000)
        )
        try reloaded.updateActiveTimerStart(to: monday.addingTimeInterval(9_700))
        try expect(
            reloaded.activeTimer?.start == monday.addingTimeInterval(9_700),
            "Active timer start must be adjustable"
        )
        let adjustedReload = try TimeTrackingStore(storageURL: storage)
        try expect(
            adjustedReload.activeTimer?.start == monday.addingTimeInterval(9_700),
            "Adjusted active timer start must persist"
        )

        try expect(ElapsedTimeParser.parse("45") == 2_700, "Bare numbers must parse as minutes")
        try expect(ElapsedTimeParser.parse("1h 30m") == 5_400, "Unit input must parse")
        try expect(ElapsedTimeParser.parse("1h30") == 5_400, "Trailing bare numbers must drop one unit level")
        try expect(ElapsedTimeParser.parse("01:30:00") == 5_400, "Clock input must parse")
        try expect(ElapsedTimeParser.parse("1:99") == nil, "Out-of-range clock minutes must be rejected")

        do {
            _ = try TimeEntry(
                projectCode: "A1B",
                workMode: .deepWork,
                start: monday,
                end: monday.addingTimeInterval(60)
            )
            throw HarnessFailure.expectation("Project codes with digits must be rejected")
        } catch TimeTrackingValidationError.invalidProjectCode {
            // Expected.
        }

        print("MussolFeinerCore harness passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw HarnessFailure.expectation(message) }
    }

    private static func isoDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)!
    }
}
