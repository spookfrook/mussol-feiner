import Foundation

public struct AnalyticsSummary: Equatable, Sendable {
    public let interval: DateInterval
    public let totalDuration: TimeInterval
    public let workModeTotals: [WorkMode: TimeInterval]
    public let projectTotals: [String: TimeInterval]
    public let averageFocusScore: Double?
    public let scoredDuration: TimeInterval

    public var meetingDuration: TimeInterval {
        (workModeTotals[.activeMeeting] ?? 0) + (workModeTotals[.passiveMeeting] ?? 0)
    }

    public func duration(for mode: WorkMode) -> TimeInterval {
        workModeTotals[mode] ?? 0
    }

    public func duration(forProject projectCode: String) -> TimeInterval {
        guard let normalized = try? ProjectCode.normalize(projectCode) else { return 0 }
        return projectTotals[normalized] ?? 0
    }
}

public struct WeeklyTrendPoint: Identifiable, Equatable, Sendable {
    public var id: Date { interval.start }

    public let interval: DateInterval
    public let totalDuration: TimeInterval
    public let workModeTotals: [WorkMode: TimeInterval]
    public let averageFocusScore: Double?
    public let totalDurationChangeFromPreviousWeek: TimeInterval?
    public let totalDurationPercentChangeFromPreviousWeek: Double?
}

public enum AnalyticsEngine {
    /// Allocates only the portion of each entry that overlaps the requested interval.
    /// This makes entries spanning midnight contribute correctly to each day or week.
    public static func summary(
        entries: [TimeEntry],
        in interval: DateInterval
    ) -> AnalyticsSummary {
        var workModeTotals = Dictionary(
            uniqueKeysWithValues: WorkMode.allCases.map { ($0, TimeInterval.zero) }
        )
        var projectTotals: [String: TimeInterval] = [:]
        var totalDuration: TimeInterval = 0
        var focusWeightedSum: Double = 0
        var scoredDuration: TimeInterval = 0

        for entry in entries {
            let duration = overlappingDuration(of: entry, with: interval)
            guard duration > 0 else { continue }

            totalDuration += duration
            workModeTotals[entry.workMode, default: 0] += duration
            projectTotals[entry.projectCode, default: 0] += duration

            if let focusScore = entry.focusScore {
                focusWeightedSum += Double(focusScore) * duration
                scoredDuration += duration
            }
        }

        return AnalyticsSummary(
            interval: interval,
            totalDuration: totalDuration,
            workModeTotals: workModeTotals,
            projectTotals: projectTotals,
            averageFocusScore: scoredDuration > 0 ? focusWeightedSum / scoredDuration : nil,
            scoredDuration: scoredDuration
        )
    }

    public static func daySummary(
        entries: [TimeEntry],
        containing date: Date,
        calendar: Calendar = .current
    ) -> AnalyticsSummary {
        summary(entries: entries, in: dayInterval(containing: date, calendar: calendar))
    }

    public static func weekSummary(
        entries: [TimeEntry],
        containing date: Date,
        calendar: Calendar = .current
    ) -> AnalyticsSummary {
        summary(entries: entries, in: weekInterval(containing: date, calendar: calendar))
    }

    public static func dayInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    /// Returns a calendar week that always runs from Monday at 00:00 up to the next
    /// Monday at 00:00, independently of the calendar's locale `firstWeekday` setting.
    public static func weekInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysSinceMonday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysSinceMonday, to: dayStart)
            ?? dayStart.addingTimeInterval(TimeInterval(-daysSinceMonday * 24 * 60 * 60))
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    /// Eight Monday-to-Sunday buckets, ordered oldest first and ending with the week
    /// containing `date`.
    public static func eightWeekTrend(
        entries: [TimeEntry],
        endingInWeekContaining date: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeeklyTrendPoint] {
        let currentWeek = weekInterval(containing: date, calendar: calendar)
        let firstWeekStart = calendar.date(byAdding: .day, value: -49, to: currentWeek.start)
            ?? currentWeek.start.addingTimeInterval(-49 * 24 * 60 * 60)

        var points: [WeeklyTrendPoint] = []
        var previousTotal: TimeInterval?

        for offset in 0..<8 {
            let start = calendar.date(byAdding: .day, value: offset * 7, to: firstWeekStart)
                ?? firstWeekStart.addingTimeInterval(TimeInterval(offset * 7 * 24 * 60 * 60))
            let end = calendar.date(byAdding: .day, value: 7, to: start)
                ?? start.addingTimeInterval(7 * 24 * 60 * 60)
            let interval = DateInterval(start: start, end: end)
            let weekSummary = summary(entries: entries, in: interval)

            let change = previousTotal.map { weekSummary.totalDuration - $0 }
            let percentChange: Double?
            if let previousTotal, previousTotal > 0 {
                percentChange = (weekSummary.totalDuration - previousTotal) / previousTotal
            } else {
                percentChange = nil
            }

            points.append(
                WeeklyTrendPoint(
                    interval: interval,
                    totalDuration: weekSummary.totalDuration,
                    workModeTotals: weekSummary.workModeTotals,
                    averageFocusScore: weekSummary.averageFocusScore,
                    totalDurationChangeFromPreviousWeek: change,
                    totalDurationPercentChangeFromPreviousWeek: percentChange
                )
            )
            previousTotal = weekSummary.totalDuration
        }

        return points
    }

    public static func overlappingDuration(
        of entry: TimeEntry,
        with interval: DateInterval
    ) -> TimeInterval {
        let overlapStart = max(entry.start, interval.start)
        let overlapEnd = min(entry.end, interval.end)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
}
