import Foundation
import XCTest
@testable import MussolFeinerCore

final class AnalyticsTests: XCTestCase {
    func testFocusAverageIsDurationWeightedAndExcludesMissingScores() throws {
        let start = Date(timeIntervalSince1970: 0)
        let entries = [
            try TimeEntry(
                projectCode: "AAA",
                workMode: .deepWork,
                start: start,
                end: start.addingTimeInterval(2 * 3_600),
                focusScore: 5
            ),
            try TimeEntry(
                projectCode: "BBB",
                workMode: .shallowWork,
                start: start.addingTimeInterval(2 * 3_600),
                end: start.addingTimeInterval(3 * 3_600),
                focusScore: 1
            ),
            try TimeEntry(
                projectCode: "CCC",
                workMode: .activeMeeting,
                start: start.addingTimeInterval(3 * 3_600),
                end: start.addingTimeInterval(13 * 3_600)
            )
        ]

        let summary = AnalyticsEngine.summary(
            entries: entries,
            in: DateInterval(start: start, duration: 24 * 3_600)
        )

        XCTAssertEqual(summary.totalDuration, 13 * 3_600)
        XCTAssertEqual(summary.scoredDuration, 3 * 3_600)
        XCTAssertEqual(summary.averageFocusScore ?? 0, 11.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(summary.duration(for: .deepWork), 2 * 3_600)
        XCTAssertEqual(summary.duration(forProject: "aaa"), 2 * 3_600)
        XCTAssertEqual(summary.meetingDuration, 10 * 3_600)
    }

    func testDayBucketsClipEntriesAtMidnight() throws {
        let calendar = utcCalendar()
        let day = date(2026, 7, 14, hour: 12, calendar: calendar)
        let midnight = date(2026, 7, 14, hour: 0, calendar: calendar)
        let entry = try TimeEntry(
            projectCode: "NIT",
            workMode: .deepWork,
            start: midnight.addingTimeInterval(-30 * 60),
            end: midnight.addingTimeInterval(90 * 60),
            focusScore: 4
        )

        let summary = AnalyticsEngine.daySummary(
            entries: [entry],
            containing: day,
            calendar: calendar
        )

        XCTAssertEqual(summary.interval.start, midnight)
        XCTAssertEqual(summary.totalDuration, 90 * 60)
        XCTAssertEqual(summary.scoredDuration, 90 * 60)
        XCTAssertEqual(summary.averageFocusScore, 4)
    }

    func testWeekAlwaysRunsMondayThroughSunday() throws {
        let calendar = utcCalendar(firstWeekday: 1)
        let sunday = date(2026, 7, 19, hour: 12, calendar: calendar)
        let monday = date(2026, 7, 13, hour: 0, calendar: calendar)
        let followingMonday = date(2026, 7, 20, hour: 0, calendar: calendar)
        let interval = AnalyticsEngine.weekInterval(containing: sunday, calendar: calendar)

        XCTAssertEqual(interval.start, monday)
        XCTAssertEqual(interval.end, followingMonday)

        let inside = try TimeEntry(
            projectCode: "SUN",
            workMode: .passiveMeeting,
            start: followingMonday.addingTimeInterval(-3_600),
            end: followingMonday
        )
        let outside = try TimeEntry(
            projectCode: "MON",
            workMode: .activeMeeting,
            start: followingMonday,
            end: followingMonday.addingTimeInterval(3_600)
        )
        let summary = AnalyticsEngine.weekSummary(
            entries: [inside, outside],
            containing: sunday,
            calendar: calendar
        )
        XCTAssertEqual(summary.totalDuration, 3_600)
        XCTAssertEqual(summary.projectTotals, ["SUN": 3_600])
    }

    func testEightWeekTrendIsOldestFirstWithWeekChanges() throws {
        let calendar = utcCalendar()
        let currentWednesday = date(2026, 7, 15, hour: 12, calendar: calendar)
        let currentWeek = AnalyticsEngine.weekInterval(
            containing: currentWednesday,
            calendar: calendar
        )
        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeek.start)!
        let entries = [
            try TimeEntry(
                projectCode: "OLD",
                workMode: .deepWork,
                start: previousWeekStart,
                end: previousWeekStart.addingTimeInterval(2 * 3_600),
                focusScore: 3
            ),
            try TimeEntry(
                projectCode: "NOW",
                workMode: .deepWork,
                start: currentWeek.start,
                end: currentWeek.start.addingTimeInterval(3 * 3_600),
                focusScore: 5
            )
        ]

        let trend = AnalyticsEngine.eightWeekTrend(
            entries: entries,
            endingInWeekContaining: currentWednesday,
            calendar: calendar
        )

        XCTAssertEqual(trend.count, 8)
        XCTAssertEqual(trend.last?.interval, currentWeek)
        XCTAssertEqual(trend[6].totalDuration, 2 * 3_600)
        XCTAssertEqual(trend[7].totalDuration, 3 * 3_600)
        XCTAssertEqual(trend[7].totalDurationChangeFromPreviousWeek, 3_600)
        XCTAssertEqual(trend[7].totalDurationPercentChangeFromPreviousWeek, 0.5)
        XCTAssertEqual(trend[7].averageFocusScore, 5)
    }

    private func utcCalendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
