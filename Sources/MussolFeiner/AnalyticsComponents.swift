import Charts
import SwiftUI

struct PeriodNavigator: View {
    let title: String
    let subtitle: String
    let previous: () -> Void
    let next: () -> Void
    let returnToCurrent: () -> Void
    var nextDisabled = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: previous) {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MussolTheme.mutedInk)
            }
            Spacer()
            Button("Current", action: returnToCurrent)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: next) {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(nextDisabled)
        }
    }
}

struct SummaryMetric: View {
    let label: String
    let value: String
    var detail: String?
    var accent = MussolTheme.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle()
                .fill(accent)
                .frame(height: 5)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(MussolTheme.mutedInk)
            Text(value)
                .font(.system(size: 23, weight: .black, design: .monospaced))
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MussolTheme.mutedInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MussolTheme.paperLight)
        .overlay(Rectangle().stroke(MussolTheme.rule, lineWidth: 1))
    }
}

struct WorkModeBreakdown: View {
    let totals: [ModeTotal]
    let color: (UIWorkMode) -> Color

    private var totalDuration: TimeInterval {
        totals.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    BlockLabel(text: "Work mode breakdown", color: MussolTheme.signalYellow)
                    Spacer()
                    Text("PRIMARY")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(MussolTheme.mutedInk)
                }
                if totalDuration > 0 {
                    HStack(spacing: 20) {
                        DonutChart(totals: totals, color: color)
                            .frame(width: 148, height: 148)
                            .overlay {
                                VStack(spacing: 1) {
                                    Text(formatHours(totalDuration))
                                        .font(.system(size: 19, weight: .black, design: .monospaced))
                                    Text("TRACKED")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundStyle(MussolTheme.mutedInk)
                                }
                            }
                        VStack(spacing: 9) {
                            ForEach(totals) { item in
                                HStack(spacing: 8) {
                                    WorkModeDot(color: color(item.mode), size: 10)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.mode.label)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(item.mode.code)
                                            .font(.system(size: 8, weight: .black, design: .monospaced))
                                            .foregroundStyle(MussolTheme.mutedInk)
                                    }
                                    Spacer()
                                    Text(formatHours(item.duration))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(percent(item.duration))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(MussolTheme.mutedInk)
                                        .frame(width: 34, alignment: .trailing)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    EmptyAnalyticsState(
                        icon: "circle.dashed",
                        title: "No tracked time",
                        message: "Clock in or add a manual entry to see your work mode mix."
                    )
                    .frame(height: 148)
                }
            }
        }
    }

    private func percent(_ duration: TimeInterval) -> String {
        guard totalDuration > 0 else { return "0%" }
        return "\(Int((duration / totalDuration * 100).rounded()))%"
    }
}

private struct DonutChart: View {
    let totals: [ModeTotal]
    let color: (UIWorkMode) -> Color

    var body: some View {
        Canvas { context, size in
            let total = totals.reduce(0) { $0 + $1.duration }
            guard total > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(1, min(size.width, size.height) / 2 - 15)
            var start = Angle.degrees(-90)
            for item in totals where item.duration > 0 {
                let sweep = item.duration / total * 360
                let gap = min(1.6, sweep * 0.12)
                let end = Angle.degrees(start.degrees + sweep - gap)
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(
                    path,
                    with: .color(color(item.mode)),
                    style: StrokeStyle(lineWidth: 24, lineCap: .butt)
                )
                start = Angle.degrees(start.degrees + sweep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Work mode donut chart")
    }
}

struct ProjectBreakdown: View {
    let totals: [ProjectTotal]

    private var displayedTotals: [ProjectTotal] {
        guard totals.count > 8 else { return totals }
        let visible = Array(totals.prefix(7))
        let otherDuration = totals.dropFirst(7).reduce(0) { $0 + $1.duration }
        return visible + [ProjectTotal(projectCode: "OTHER", duration: otherDuration)]
    }

    private var maxDuration: TimeInterval {
        max(displayedTotals.map(\.duration).max() ?? 1, 1)
    }

    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    BlockLabel(text: "Project breakdown", color: MussolTheme.ink)
                    Spacer()
                    Text("SECONDARY")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(MussolTheme.mutedInk)
                }
                if totals.isEmpty {
                    EmptyAnalyticsState(
                        icon: "square.stack.3d.up.slash",
                        title: "No projects yet",
                        message: "Three-letter codes group automatically here."
                    )
                    .frame(height: 120)
                } else {
                    VStack(spacing: 11) {
                        ForEach(Array(displayedTotals.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(MussolTheme.mutedInk)
                                    .frame(width: 14)
                                Text(item.projectCode)
                                    .font(.system(size: 12, weight: .black, design: .monospaced))
                                    .frame(width: 48, alignment: .leading)
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(MussolTheme.ink.opacity(0.08))
                                        Rectangle()
                                            .fill(index == 0 ? MussolTheme.signalYellow : MussolTheme.ink.opacity(0.72))
                                            .frame(width: geometry.size.width * item.duration / maxDuration)
                                    }
                                }
                                .frame(height: 10)
                                Text(formatHours(item.duration))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct EntryRow: View {
    let entry: UIEntry
    let color: Color
    let clippingInterval: DateInterval
    let edit: () -> Void
    let delete: () -> Void

    private var displayedStart: Date {
        max(entry.startDate, clippingInterval.start)
    }

    private var displayedEnd: Date {
        min(entry.endDate, clippingInterval.end)
    }

    private var displayedDuration: TimeInterval {
        max(0, displayedEnd.timeIntervalSince(displayedStart))
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(color)
                .frame(width: 7)
            Text(entry.projectCode)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mode.label)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(formatEnglishDate(displayedStart, "HH:mm")) to \(formatEnglishDate(displayedEnd, "HH:mm"))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MussolTheme.mutedInk)
            }
            Spacer()
            if let score = entry.focusScore {
                FocusScorePips(score: score, color: color)
                    .help("Focus Score: \(score) of 5")
            }
            Text(formatClock(displayedDuration))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .frame(width: 68, alignment: .trailing)
            Menu {
                Button("Edit", action: edit)
                Button("Delete", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(minHeight: 48)
        .padding(.trailing, 8)
        .background(MussolTheme.paperLight)
        .overlay(Rectangle().stroke(MussolTheme.rule, lineWidth: 1))
    }
}

struct FocusScorePips: View {
    let score: Int
    var color = MussolTheme.signalYellow

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Rectangle()
                    .fill(index <= score ? color : MussolTheme.ink.opacity(0.12))
                    .frame(width: 4, height: 11)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus Score \(score) out of 5")
    }
}

struct DailyStackedBarChart: View {
    let totals: [DailyModeTotal]
    let color: (UIWorkMode) -> Color

    var body: some View {
        Chart(totals) { item in
            BarMark(
                x: .value("Day", item.day, unit: .day),
                y: .value("Hours", item.duration / 3600)
            )
            .foregroundStyle(color(item.mode))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(MussolTheme.ink.opacity(0.10))
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(hours, specifier: "%.0f")h")
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(MussolTheme.ink.opacity(0.025))
        }
    }
}

struct WeeklyStackedBarChart: View {
    let totals: [WeeklyModeTotal]
    let color: (UIWorkMode) -> Color

    private var weekStarts: [Date] {
        Array(Set(totals.map(\.weekStart))).sorted()
    }

    private var xDomain: ClosedRange<Date> {
        let first = weekStarts.first ?? Date()
        let last = weekStarts.last ?? first
        let start = Calendar.mondayFirst.date(byAdding: .day, value: -4, to: first) ?? first
        let end = Calendar.mondayFirst.date(byAdding: .day, value: 4, to: last) ?? last
        return start...max(end, start.addingTimeInterval(86400))
    }

    var body: some View {
        ZStack {
            Chart(totals) { item in
                BarMark(
                    x: .value("Week", item.weekStart),
                    y: .value("Hours", item.duration / 3600)
                )
                .foregroundStyle(color(item.mode))
            }
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: weekStarts) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel {
                        if let weekStart = value.as(Date.self) {
                            Text(formatEnglishDate(weekStart, "MMM d"))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(MussolTheme.ink.opacity(0.10))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(hours, specifier: "%.0f")h")
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummaryText)
    }

    private func accessibilitySummary(for weekStart: Date) -> String {
        let values = UIWorkMode.allCases.map { mode -> String in
            let duration = totals.first {
                $0.weekStart == weekStart && $0.mode == mode
            }?.duration ?? 0
            return "\(mode.label) \(formatHours(duration))"
        }
        let total = totals
            .filter { $0.weekStart == weekStart }
            .reduce(0) { $0 + $1.duration }
        return "Week of \(formatEnglishDate(weekStart, "MMMM d, yyyy")): \(values.joined(separator: ", ")). Total \(formatHours(total))."
    }

    private var accessibilitySummaryText: String {
        (["Time by work mode across eight Monday-starting weeks."]
            + weekStarts.map(accessibilitySummary(for:)))
            .joined(separator: " ")
    }
}

struct FocusTrendChart: View {
    let points: [WeeklyFocusPoint]

    var body: some View {
        let scored = points.compactMap { point -> ScoredFocusPoint? in
            guard let score = point.score else { return nil }
            return ScoredFocusPoint(weekStart: point.weekStart, score: score)
        }
        let weekStarts = points.map(\.weekStart).sorted()
        let firstWeek = weekStarts.first ?? Date()
        let lastWeek = weekStarts.last ?? firstWeek
        let domainStart = Calendar.mondayFirst.date(byAdding: .day, value: -4, to: firstWeek) ?? firstWeek
        let paddedEnd = Calendar.mondayFirst.date(byAdding: .day, value: 4, to: lastWeek) ?? lastWeek
        let domainEnd = max(paddedEnd, domainStart.addingTimeInterval(86400))
        ZStack {
            Chart(scored) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Focus Score", point.score)
                )
                .foregroundStyle(MussolTheme.ink)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Focus Score", point.score)
                )
                .foregroundStyle(MussolTheme.signalYellow)
                .symbolSize(48)
            }
            .chartXScale(domain: domainStart...domainEnd)
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(position: .leading, values: [1, 2, 3, 4, 5])
            }
            .chartXAxis {
                AxisMarks(values: weekStarts) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel {
                        if let weekStart = value.as(Date.self) {
                            Text(formatEnglishDate(weekStart, "MMM d"))
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focusAccessibilitySummaryText)
    }

    private func focusAccessibilitySummary(_ point: WeeklyFocusPoint) -> String {
        let score = point.score.map { String(format: "%.1f out of 5", $0) } ?? "not scored"
        return "Week of \(formatEnglishDate(point.weekStart, "MMMM d, yyyy")): Focus Score \(score)."
    }

    private var focusAccessibilitySummaryText: String {
        (["Duration-weighted Focus Score across eight Monday-starting weeks."]
            + points.sorted(by: { $0.weekStart < $1.weekStart }).map(focusAccessibilitySummary))
            .joined(separator: " ")
    }
}

private struct ScoredFocusPoint: Identifiable {
    let weekStart: Date
    let score: Double
    var id: Date { weekStart }
}

struct EmptyAnalyticsState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(MussolTheme.mutedInk)
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(MussolTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
