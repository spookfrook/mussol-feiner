import Foundation

enum UIWorkMode: String, CaseIterable, Identifiable, Codable {
    case deepWork
    case shallowWork
    case activeMeeting
    case passiveMeeting

    var id: String { rawValue }

    var code: String {
        switch self {
        case .deepWork: return "DPW"
        case .shallowWork: return "SHW"
        case .activeMeeting: return "AMT"
        case .passiveMeeting: return "PMT"
        }
    }

    var label: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .shallowWork: return "Shallow Work"
        case .activeMeeting: return "Active Meeting"
        case .passiveMeeting: return "Passive Meeting"
        }
    }

    var defaultColorHex: String {
        switch self {
        case .deepWork: return "#F2AB0D"
        case .shallowWork: return "#0690A8"
        case .activeMeeting: return "#D6281F"
        case .passiveMeeting: return "#5C3885"
        }
    }
}

struct UIEntry: Identifiable, Equatable {
    let id: UUID
    var projectCode: String
    var mode: UIWorkMode
    var startDate: Date
    var endDate: Date
    var focusScore: Int?

    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
}

struct UIActiveTimer: Equatable {
    var projectCode: String
    var mode: UIWorkMode
    var startedAt: Date
}

struct EntryDraft: Identifiable {
    let id = UUID()
    var editingID: UUID?
    var projectCode = ""
    var mode: UIWorkMode = .deepWork
    var startDate = Date()
    var endDate = Date().addingTimeInterval(3600)
    var focusScore: Int?

    init() {}

    init(entry: UIEntry) {
        editingID = entry.id
        projectCode = entry.projectCode
        mode = entry.mode
        startDate = entry.startDate
        endDate = entry.endDate
        focusScore = entry.focusScore
    }
}

struct ModeTotal: Identifiable {
    let mode: UIWorkMode
    let duration: TimeInterval
    var id: String { mode.id }
}

struct ProjectTotal: Identifiable {
    let projectCode: String
    let duration: TimeInterval
    var id: String { projectCode }
}

struct DailyModeTotal: Identifiable {
    let day: Date
    let mode: UIWorkMode
    let duration: TimeInterval
    var id: String { "\(day.timeIntervalSinceReferenceDate)-\(mode.rawValue)" }
}

struct WeeklyModeTotal: Identifiable {
    let weekStart: Date
    let mode: UIWorkMode
    let duration: TimeInterval
    var id: String { "\(weekStart.timeIntervalSinceReferenceDate)-\(mode.rawValue)" }
}

struct WeeklyFocusPoint: Identifiable {
    let weekStart: Date
    let score: Double?
    var id: Date { weekStart }
}

extension String {
    var projectCode: String {
        let letters = uppercased().unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return String(String.UnicodeScalarView(letters).prefix(3))
    }
}

extension Calendar {
    static var mondayFirst: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func monday(containing date: Date) -> Date {
        let start = startOfDay(for: date)
        let weekday = component(.weekday, from: start)
        let offset = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -offset, to: start) ?? start
    }
}
