import Combine
import Foundation
#if canImport(MussolFeinerCore)
import MussolFeinerCore
#endif
import SwiftUI

@MainActor
final class TrackerViewModel: ObservableObject {
    @Published private(set) var entries: [UIEntry] = []
    @Published private(set) var activeTimer: UIActiveTimer?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var pendingFocusEntryID: UUID?
    @Published var alertMessage: String?
    @Published private(set) var modeColorHexes: [UIWorkMode: String]
    @Published private(set) var popoverFocusRequest = 0

    let store: TimeTrackingStore

    private var calendar: Calendar { Calendar.mondayFirst }
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var queuedFocusEntryIDs: [UUID] = []

    init(store: TimeTrackingStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        self.modeColorHexes = Dictionary(uniqueKeysWithValues: UIWorkMode.allCases.map { mode in
            let key = Self.colorDefaultsKey(for: mode)
            return (mode, defaults.string(forKey: key) ?? mode.defaultColorHex)
        })

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.synchronizeFromStore() }
            }
            .store(in: &cancellables)

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in self?.updateElapsed(at: now) }
            .store(in: &cancellables)

        synchronizeFromStore()
    }

    func startTimer(projectCode: String, mode: UIWorkMode) {
        do {
            if let stopped = try store.startTimer(
                projectCode: projectCode.projectCode,
                workMode: coreMode(mode),
                at: Date()
            ) {
                enqueueFocusPrompt(for: stopped.id)
            }
            synchronizeFromStore()
        } catch {
            present(error)
        }
    }

    func requestProjectFieldFocus() {
        popoverFocusRequest &+= 1
    }

    func stopTimer() {
        do {
            if let stopped = try store.stopTimer(at: Date(), focusScore: nil) {
                enqueueFocusPrompt(for: stopped.id)
            }
            synchronizeFromStore()
        } catch {
            present(error)
        }
    }

    func setPendingFocus(_ score: Int) {
        guard let id = pendingFocusEntryID,
              let current = store.entries.first(where: { $0.id == id }) else {
            advanceFocusPrompt()
            return
        }
        do {
            let updated = try TimeEntry(
                id: current.id,
                projectCode: current.projectCode,
                workMode: current.workMode,
                start: current.start,
                end: current.end,
                focusScore: score
            )
            try store.update(updated)
            advanceFocusPrompt()
            synchronizeFromStore()
        } catch {
            present(error)
        }
    }

    func skipPendingFocus() {
        advanceFocusPrompt()
    }

    func save(_ draft: EntryDraft) {
        let code = draft.projectCode.projectCode
        guard code.count == 3 else {
            alertMessage = "Project code must be exactly three letters."
            return
        }
        guard draft.endDate > draft.startDate else {
            alertMessage = "End time must be later than start time."
            return
        }

        do {
            if let id = draft.editingID {
                let entry = try TimeEntry(
                    id: id,
                    projectCode: code,
                    workMode: coreMode(draft.mode),
                    start: draft.startDate,
                    end: draft.endDate,
                    focusScore: draft.focusScore
                )
                try store.update(entry)
            } else {
                _ = try store.addEntry(
                    projectCode: code,
                    workMode: coreMode(draft.mode),
                    start: draft.startDate,
                    end: draft.endDate,
                    focusScore: draft.focusScore
                )
            }
            synchronizeFromStore()
        } catch {
            present(error)
        }
    }

    func delete(_ entry: UIEntry) {
        do {
            try store.delete(id: entry.id)
            queuedFocusEntryIDs.removeAll(where: { $0 == entry.id })
            if pendingFocusEntryID == entry.id { advanceFocusPrompt() }
            synchronizeFromStore()
        } catch {
            present(error)
        }
    }

    func color(for mode: UIWorkMode) -> Color {
        MussolTheme.color(hex: modeColorHexes[mode] ?? mode.defaultColorHex)
    }

    func setColor(_ color: Color, for mode: UIWorkMode) {
        guard let hex = MussolTheme.hex(color: color) else { return }
        modeColorHexes[mode] = hex
        defaults.set(hex, forKey: Self.colorDefaultsKey(for: mode))
    }

    func resetColors() {
        for mode in UIWorkMode.allCases {
            modeColorHexes[mode] = mode.defaultColorHex
            defaults.removeObject(forKey: Self.colorDefaultsKey(for: mode))
        }
    }

    func entries(on day: Date) -> [UIEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return entries(in: interval).sorted { $0.startDate > $1.startDate }
    }

    func entries(in interval: DateInterval) -> [UIEntry] {
        entries.filter { $0.endDate > interval.start && $0.startDate < interval.end }
    }

    func dayInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86400)
    }

    func weekInterval(containing date: Date) -> DateInterval {
        let start = calendar.monday(containing: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(604800)
        return DateInterval(start: start, end: end)
    }

    func totalDuration(in interval: DateInterval) -> TimeInterval {
        analyticsEntries(in: interval).reduce(0) { $0 + clippedDuration(of: $1, in: interval) }
    }

    func duration(of mode: UIWorkMode, in interval: DateInterval) -> TimeInterval {
        analyticsEntries(in: interval)
            .filter { $0.mode == mode }
            .reduce(0) { $0 + clippedDuration(of: $1, in: interval) }
    }

    func modeTotals(in interval: DateInterval) -> [ModeTotal] {
        UIWorkMode.allCases.map { mode in
            ModeTotal(mode: mode, duration: duration(of: mode, in: interval))
        }
    }

    func projectTotals(in interval: DateInterval) -> [ProjectTotal] {
        let grouped = Dictionary(grouping: analyticsEntries(in: interval), by: \.projectCode)
        return grouped.map { code, entries in
            ProjectTotal(
                projectCode: code,
                duration: entries.reduce(0) { $0 + clippedDuration(of: $1, in: interval) }
            )
        }
        .sorted { left, right in
            left.duration == right.duration
                ? left.projectCode < right.projectCode
                : left.duration > right.duration
        }
    }

    func weightedFocus(in interval: DateInterval) -> Double? {
        let scored = analyticsEntries(in: interval).filter { $0.focusScore != nil }
        let weight = scored.reduce(0) { $0 + clippedDuration(of: $1, in: interval) }
        guard weight > 0 else { return nil }
        let total = scored.reduce(0.0) { partial, entry in
            partial + Double(entry.focusScore ?? 0) * clippedDuration(of: entry, in: interval)
        }
        return total / weight
    }

    func dailyModeTotals(in week: DateInterval) -> [DailyModeTotal] {
        (0..<7).flatMap { dayOffset -> [DailyModeTotal] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: week.start) else { return [] }
            let interval = dayInterval(containing: day)
            return UIWorkMode.allCases.map { mode in
                DailyModeTotal(day: day, mode: mode, duration: duration(of: mode, in: interval))
            }
        }
    }

    func lastEightWeeks(endingIn weekContainingDate: Date = Date()) -> [DateInterval] {
        let current = weekInterval(containing: weekContainingDate)
        return (0..<8).reversed().map { offset in
            let start = calendar.date(byAdding: .day, value: -(offset * 7), to: current.start) ?? current.start
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(604800)
            return DateInterval(start: start, end: end)
        }
    }

    func weeklyModeTotals(endingIn weekContainingDate: Date = Date()) -> [WeeklyModeTotal] {
        lastEightWeeks(endingIn: weekContainingDate).flatMap { week in
            UIWorkMode.allCases.map { mode in
                WeeklyModeTotal(weekStart: week.start, mode: mode, duration: duration(of: mode, in: week))
            }
        }
    }

    func weeklyFocusPoints(endingIn weekContainingDate: Date = Date()) -> [WeeklyFocusPoint] {
        lastEightWeeks(endingIn: weekContainingDate).map { week in
            WeeklyFocusPoint(weekStart: week.start, score: weightedFocus(in: week))
        }
    }

    private func synchronizeFromStore() {
        entries = store.entries.map { entry in
            UIEntry(
                id: entry.id,
                projectCode: entry.projectCode,
                mode: uiMode(entry.workMode),
                startDate: entry.start,
                endDate: entry.end,
                focusScore: entry.focusScore
            )
        }
        .sorted { $0.startDate > $1.startDate }

        if let active = store.activeTimer {
            activeTimer = UIActiveTimer(
                projectCode: active.projectCode,
                mode: uiMode(active.workMode),
                startedAt: active.start
            )
            elapsed = active.elapsed(at: Date())
        } else {
            activeTimer = nil
            elapsed = 0
        }
    }

    private func updateElapsed(at date: Date) {
        guard let active = store.activeTimer else {
            if elapsed != 0 { elapsed = 0 }
            return
        }
        elapsed = active.elapsed(at: date)
    }

    private func clippedDuration(of entry: UIEntry, in interval: DateInterval) -> TimeInterval {
        let start = max(entry.startDate, interval.start)
        let end = min(entry.endDate, interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    /// Analytics are live while a timer is running, even though the editable entry list
    /// remains limited to completed sessions. The projected entry is never persisted.
    private func analyticsEntries(in interval: DateInterval, at now: Date = Date()) -> [UIEntry] {
        var result = entries(in: interval)
        guard let activeTimer,
              now > activeTimer.startedAt,
              now > interval.start,
              activeTimer.startedAt < interval.end else {
            return result
        }

        result.append(
            UIEntry(
                id: Self.projectedActiveEntryID,
                projectCode: activeTimer.projectCode,
                mode: activeTimer.mode,
                startDate: activeTimer.startedAt,
                endDate: now,
                focusScore: nil
            )
        )
        return result
    }

    private func coreMode(_ mode: UIWorkMode) -> WorkMode {
        WorkMode(rawValue: mode.rawValue) ?? .deepWork
    }

    private func uiMode(_ mode: WorkMode) -> UIWorkMode {
        UIWorkMode(rawValue: mode.rawValue) ?? .deepWork
    }

    private func present(_ error: Error) {
        alertMessage = error.localizedDescription
    }

    private func enqueueFocusPrompt(for entryID: UUID) {
        guard pendingFocusEntryID != entryID,
              !queuedFocusEntryIDs.contains(entryID) else { return }
        if pendingFocusEntryID == nil {
            pendingFocusEntryID = entryID
        } else {
            queuedFocusEntryIDs.append(entryID)
        }
    }

    private func advanceFocusPrompt() {
        pendingFocusEntryID = queuedFocusEntryIDs.isEmpty
            ? nil
            : queuedFocusEntryIDs.removeFirst()
    }

    private static func colorDefaultsKey(for mode: UIWorkMode) -> String {
        "workModeColor.\(mode.rawValue)"
    }

    private static let projectedActiveEntryID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!
}
