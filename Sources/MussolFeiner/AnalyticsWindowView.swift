import SwiftUI

enum AnalyticsTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case trends = "Trends"
    var id: String { rawValue }
}

enum UIExportFormat: String, CaseIterable {
    case json = "JSON"
    case csv = "CSV"
    case markdown = "Markdown"
}

struct AnalyticsWindowView: View {
    @ObservedObject var model: TrackerViewModel
    let export: (UIExportFormat, DateInterval?) -> Void

    @State private var selectedTab: AnalyticsTab = .today
    @State private var selectedDay = Date()
    @State private var selectedWeek = Calendar.mondayFirst.monday(containing: Date())
    @State private var entryDraft: EntryDraft?
    @State private var showSettings = false
    @State private var entryPendingDeletion: UIEntry?

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                appHeader
                Divider().overlay(MussolTheme.ink.opacity(0.45))
                TimerControlBar(model: model)
                Divider().overlay(MussolTheme.ink.opacity(0.45))
                Group {
                    switch selectedTab {
                    case .today:
                        TodayAnalyticsView(
                            model: model,
                            selectedDay: $selectedDay,
                            addEntry: { entryDraft = newDraft(on: selectedDay) },
                            editEntry: { entryDraft = EntryDraft(entry: $0) },
                            deleteEntry: { entryPendingDeletion = $0 }
                        )
                    case .week:
                        WeekAnalyticsView(
                            model: model,
                            selectedWeek: $selectedWeek,
                            addEntry: { entryDraft = newDraft(on: selectedWeek) }
                        )
                    case .trends:
                        TrendsAnalyticsView(model: model)
                    }
                }
            }
        }
        .foregroundStyle(MussolTheme.ink)
        .tint(MussolTheme.ink)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.calendar, Calendar.mondayFirst)
        .environment(\.colorScheme, .light)
        .frame(minWidth: 820, idealWidth: 980, minHeight: 640, idealHeight: 760)
        .sheet(item: $entryDraft) { draft in
            EntryEditorView(model: model, draft: draft)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
        .alert("Mussol Feiner", isPresented: alertPresented) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "Something went wrong.")
        }
        .confirmationDialog(
            "Delete this time entry?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete entry", role: .destructive) {
                if let entryPendingDeletion { model.delete(entryPendingDeletion) }
                entryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { entryPendingDeletion = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var appHeader: some View {
        HStack(spacing: 18) {
            HStack(spacing: 10) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MUSSOL FEINER")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .tracking(1)
                    Text("Your mental energy ledger")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MussolTheme.mutedInk)
                }
            }

            Picker("View", selection: $selectedTab) {
                ForEach(AnalyticsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 350)

            Spacer()

            Menu {
                Menu("Export current view") {
                    ForEach(UIExportFormat.allCases, id: \.rawValue) { format in
                        Button(format.rawValue) { export(format, currentInterval) }
                    }
                }
                Menu("Export all data") {
                    ForEach(UIExportFormat.allCases, id: \.rawValue) { format in
                        Button(format.rawValue) { export(format, nil) }
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(MussolTheme.ink)
            .fixedSize()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Work mode colors")
            .accessibilityLabel("Work mode color settings")
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
        .background(MussolTheme.paperLight.opacity(0.74))
    }

    private var currentInterval: DateInterval {
        switch selectedTab {
        case .today:
            return model.dayInterval(containing: selectedDay)
        case .week:
            return model.weekInterval(containing: selectedWeek)
        case .trends:
            let weeks = model.lastEightWeeks()
            return DateInterval(start: weeks.first?.start ?? Date(), end: weeks.last?.end ?? Date())
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { entryPendingDeletion != nil },
            set: { if !$0 { entryPendingDeletion = nil } }
        )
    }

    private func newDraft(on date: Date) -> EntryDraft {
        var draft = EntryDraft()
        let isToday = Calendar.current.isDateInToday(date)
        let components = isToday
            ? Calendar.current.dateComponents([.hour, .minute], from: Date())
            : DateComponents(hour: 9, minute: 0)
        let start = Calendar.current.date(
            bySettingHour: components.hour ?? 9,
            minute: components.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
        draft.startDate = start
        draft.endDate = start.addingTimeInterval(3600)
        return draft
    }
}

private struct TodayAnalyticsView: View {
    @ObservedObject var model: TrackerViewModel
    @Binding var selectedDay: Date
    let addEntry: () -> Void
    let editEntry: (UIEntry) -> Void
    let deleteEntry: (UIEntry) -> Void

    private var interval: DateInterval { model.dayInterval(containing: selectedDay) }
    private var dayEntries: [UIEntry] { model.entries(on: selectedDay) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PeriodNavigator(
                    title: dayTitle,
                    subtitle: formatEnglishDate(selectedDay, "EEEE, MMMM d, yyyy"),
                    previous: { moveDay(-1) },
                    next: { moveDay(1) },
                    returnToCurrent: { selectedDay = Date() },
                    nextDisabled: Calendar.current.isDateInToday(selectedDay)
                )

                HStack(spacing: 12) {
                    SummaryMetric(
                        label: "Tracked",
                        value: formatHours(model.totalDuration(in: interval)),
                        detail: "\(dayEntries.count) \(dayEntries.count == 1 ? "entry" : "entries")",
                        accent: MussolTheme.ink
                    )
                    SummaryMetric(
                        label: "Deep Work",
                        value: formatHours(model.duration(of: .deepWork, in: interval)),
                        detail: "Individual sustained focus",
                        accent: model.color(for: .deepWork)
                    )
                    SummaryMetric(
                        label: "Meetings",
                        value: formatHours(
                            model.duration(of: .activeMeeting, in: interval)
                                + model.duration(of: .passiveMeeting, in: interval)
                        ),
                        detail: "Active + passive",
                        accent: model.color(for: .activeMeeting)
                    )
                    SummaryMetric(
                        label: "Focus Score",
                        value: focusText,
                        detail: "Weighted by duration",
                        accent: MussolTheme.signalYellow
                    )
                }

                HStack(alignment: .top, spacing: 18) {
                    WorkModeBreakdown(totals: model.modeTotals(in: interval), color: { model.color(for: $0) })
                        .frame(maxWidth: .infinity)
                    ProjectBreakdown(totals: model.projectTotals(in: interval))
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        BlockLabel(text: "Daily entries", color: MussolTheme.ink)
                        Spacer()
                        Button(action: addEntry) {
                            Label("Add manual entry", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryInkButtonStyle())
                    }
                    if dayEntries.isEmpty {
                        EmptyAnalyticsState(
                            icon: "clock.badge.questionmark",
                            title: "Nothing logged on this day",
                            message: "Use the menu-bar timer or add a manual entry."
                        )
                        .frame(height: 140)
                        .background(MussolTheme.paperLight)
                        .overlay(Rectangle().stroke(MussolTheme.rule, lineWidth: 1))
                    } else {
                        LazyVStack(spacing: 7) {
                            ForEach(dayEntries) { entry in
                                EntryRow(
                                    entry: entry,
                                    color: model.color(for: entry.mode),
                                    clippingInterval: interval,
                                    edit: { editEntry(entry) },
                                    delete: { deleteEntry(entry) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(selectedDay) { return "TODAY" }
        if Calendar.current.isDateInYesterday(selectedDay) { return "YESTERDAY" }
        return formatEnglishDate(selectedDay, "MMM d").uppercased()
    }

    private var focusText: String {
        guard let value = model.weightedFocus(in: interval) else { return "N/A" }
        return String(format: "%.1f", value)
    }

    private func moveDay(_ offset: Int) {
        selectedDay = Calendar.current.date(byAdding: .day, value: offset, to: selectedDay) ?? selectedDay
    }
}

private struct WeekAnalyticsView: View {
    @ObservedObject var model: TrackerViewModel
    @Binding var selectedWeek: Date
    let addEntry: () -> Void

    private var interval: DateInterval { model.weekInterval(containing: selectedWeek) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PeriodNavigator(
                    title: "WEEK",
                    subtitle: weekSubtitle,
                    previous: { moveWeek(-1) },
                    next: { moveWeek(1) },
                    returnToCurrent: { selectedWeek = Calendar.mondayFirst.monday(containing: Date()) },
                    nextDisabled: interval.contains(Date())
                )

                HStack(spacing: 12) {
                    SummaryMetric(
                        label: "Tracked",
                        value: formatHours(model.totalDuration(in: interval)),
                        detail: "Monday to Sunday",
                        accent: MussolTheme.ink
                    )
                    SummaryMetric(
                        label: "Deep Work",
                        value: formatHours(model.duration(of: .deepWork, in: interval)),
                        detail: "Sustained focus capacity",
                        accent: model.color(for: .deepWork)
                    )
                    SummaryMetric(
                        label: "Shallow Work",
                        value: formatHours(model.duration(of: .shallowWork, in: interval)),
                        detail: "Fragmentable individual work",
                        accent: model.color(for: .shallowWork)
                    )
                    SummaryMetric(
                        label: "Focus Score",
                        value: focusText,
                        detail: "Weighted by duration",
                        accent: MussolTheme.signalYellow
                    )
                }

                InkCard {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            BlockLabel(text: "Daily load", color: MussolTheme.ink)
                            Spacer()
                            WorkModeInlineLegend(model: model)
                        }
                        DailyStackedBarChart(totals: model.dailyModeTotals(in: interval), color: { model.color(for: $0) })
                            .frame(height: 225)
                    }
                }

                HStack(alignment: .top, spacing: 18) {
                    WorkModeBreakdown(totals: model.modeTotals(in: interval), color: { model.color(for: $0) })
                        .frame(maxWidth: .infinity)
                    ProjectBreakdown(totals: model.projectTotals(in: interval))
                        .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("Missing time from this week?")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MussolTheme.mutedInk)
                    Spacer()
                    Button(action: addEntry) {
                        Label("Add manual entry", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryInkButtonStyle())
                }
            }
            .padding(22)
        }
    }

    private var weekSubtitle: String {
        let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(formatEnglishDate(interval.start, "MMM d")) to \(formatEnglishDate(inclusiveEnd, "MMM d, yyyy"))"
    }

    private var focusText: String {
        guard let value = model.weightedFocus(in: interval) else { return "N/A" }
        return String(format: "%.1f", value)
    }

    private func moveWeek(_ offset: Int) {
        selectedWeek = Calendar.mondayFirst.date(byAdding: .day, value: offset * 7, to: selectedWeek) ?? selectedWeek
    }
}

private struct TrendsAnalyticsView: View {
    @ObservedObject var model: TrackerViewModel

    private var weeks: [DateInterval] { model.lastEightWeeks() }
    private var current: DateInterval { weeks.last ?? model.weekInterval(containing: Date()) }
    private var previous: DateInterval? { weeks.dropLast().last }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("8-WEEK TRENDS")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                        Text("Eight Monday-starting weeks, including this week to date")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MussolTheme.mutedInk)
                    }
                    Spacer()
                    Text("\(weeks.first.map { formatEnglishDate($0.start, "MMM d") } ?? "") TO NOW")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(MussolTheme.mutedInk)
                }

                HStack(spacing: 12) {
                    SummaryMetric(
                        label: "This week",
                        value: formatHours(model.totalDuration(in: current)),
                        detail: weekDelta,
                        accent: MussolTheme.ink
                    )
                    SummaryMetric(
                        label: "Deep Work",
                        value: formatHours(model.duration(of: .deepWork, in: current)),
                        detail: deepDelta,
                        accent: model.color(for: .deepWork)
                    )
                    SummaryMetric(
                        label: "Meetings",
                        value: formatHours(
                            model.duration(of: .activeMeeting, in: current)
                                + model.duration(of: .passiveMeeting, in: current)
                        ),
                        detail: "Active + passive",
                        accent: model.color(for: .activeMeeting)
                    )
                    SummaryMetric(
                        label: "Focus Score",
                        value: focusText,
                        detail: "Weighted by duration",
                        accent: MussolTheme.signalYellow
                    )
                }

                InkCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            BlockLabel(text: "Time by work mode", color: MussolTheme.ink)
                            Spacer()
                            WorkModeInlineLegend(model: model)
                        }
                        WeeklyStackedBarChart(totals: model.weeklyModeTotals(), color: { model.color(for: $0) })
                            .frame(height: 250)
                    }
                }

                InkCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            BlockLabel(text: "Focus performance", color: MussolTheme.signalYellow)
                            Spacer()
                            Text("DURATION-WEIGHTED · SCORED ENTRIES ONLY")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(MussolTheme.mutedInk)
                        }
                        if model.weeklyFocusPoints().contains(where: { $0.score != nil }) {
                            FocusTrendChart(points: model.weeklyFocusPoints())
                                .frame(height: 190)
                        } else {
                            EmptyAnalyticsState(
                                icon: "scope",
                                title: "No Focus Scores yet",
                                message: "Score a stopped timer or manual entry to reveal the trend."
                            )
                            .frame(height: 190)
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    private var focusText: String {
        guard let value = model.weightedFocus(in: current) else { return "N/A" }
        return String(format: "%.1f", value)
    }

    private var weekDelta: String {
        guard let previous else { return "No previous comparison" }
        return deltaText(current: model.totalDuration(in: current), previous: model.totalDuration(in: comparisonInterval(for: previous)))
    }

    private var deepDelta: String {
        guard let previous else { return "No previous comparison" }
        return deltaText(
            current: model.duration(of: .deepWork, in: current),
            previous: model.duration(of: .deepWork, in: comparisonInterval(for: previous))
        )
    }

    private func comparisonInterval(for previousWeek: DateInterval) -> DateInterval {
        let elapsed = min(max(0, Date().timeIntervalSince(current.start)), current.duration)
        return DateInterval(start: previousWeek.start, duration: elapsed)
    }

    private func deltaText(current: TimeInterval, previous: TimeInterval) -> String {
        guard previous > 0 else { return current > 0 ? "New vs last week" : "No previous time" }
        let percent = Int((((current - previous) / previous) * 100).rounded())
        return "\(percent >= 0 ? "+" : "")\(percent)% vs last week"
    }
}

private struct WorkModeInlineLegend: View {
    @ObservedObject var model: TrackerViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(UIWorkMode.allCases) { mode in
                HStack(spacing: 4) {
                    WorkModeDot(color: model.color(for: mode), size: 7)
                    Text(mode.code)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                }
            }
        }
    }
}
