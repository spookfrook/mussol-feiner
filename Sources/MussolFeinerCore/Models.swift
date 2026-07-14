import Foundation

public enum WorkMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case deepWork
    case shallowWork
    case activeMeeting
    case passiveMeeting

    public var id: String { rawValue }

    public var code: String {
        switch self {
        case .deepWork: return "DPW"
        case .shallowWork: return "SHW"
        case .activeMeeting: return "AMT"
        case .passiveMeeting: return "PMT"
        }
    }

    public var label: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .shallowWork: return "Shallow Work"
        case .activeMeeting: return "Active Meeting"
        case .passiveMeeting: return "Passive Meeting"
        }
    }

    /// A high-contrast starting palette. The app may persist user-selected colors separately.
    public var defaultColorHex: String {
        switch self {
        case .deepWork: return "#F2AB0D"
        case .shallowWork: return "#0690A8"
        case .activeMeeting: return "#D6281F"
        case .passiveMeeting: return "#5C3885"
        }
    }
}

public enum TimeTrackingValidationError: Error, Equatable, LocalizedError, Sendable {
    case invalidProjectCode(String)
    case endPrecedesStart
    case invalidFocusScore(Int)
    case entryNotFound(UUID)
    case noActiveTimer

    public var errorDescription: String? {
        switch self {
        case .invalidProjectCode:
            return "Project code must contain exactly three letters."
        case .endPrecedesStart:
            return "End time cannot precede start time."
        case .invalidFocusScore:
            return "Focus score must be between 1 and 5."
        case .entryNotFound:
            return "The time entry could not be found."
        case .noActiveTimer:
            return "There is no active timer."
        }
    }
}

public enum ProjectCode {
    /// Trims surrounding whitespace, then uppercases and validates an exact three-letter code.
    public static func normalize(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.uppercased(with: Locale(identifier: "en_US_POSIX"))

        guard normalized.count == 3,
              normalized.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else {
            throw TimeTrackingValidationError.invalidProjectCode(rawValue)
        }

        return normalized
    }
}

public struct TimeEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let projectCode: String
    public let workMode: WorkMode
    public let start: Date
    public let end: Date
    public let focusScore: Int?

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    public init(
        id: UUID = UUID(),
        projectCode: String,
        workMode: WorkMode,
        start: Date,
        end: Date,
        focusScore: Int? = nil
    ) throws {
        guard end >= start else {
            throw TimeTrackingValidationError.endPrecedesStart
        }
        if let focusScore, !(1...5).contains(focusScore) {
            throw TimeTrackingValidationError.invalidFocusScore(focusScore)
        }

        self.id = id
        self.projectCode = try ProjectCode.normalize(projectCode)
        self.workMode = workMode
        self.start = start
        self.end = end
        self.focusScore = focusScore
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectCode, workMode, start, end, focusScore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let projectCode = try container.decode(String.self, forKey: .projectCode)
        let workMode = try container.decode(WorkMode.self, forKey: .workMode)
        let start = try container.decode(Date.self, forKey: .start)
        let end = try container.decode(Date.self, forKey: .end)
        let focusScore = try container.decodeIfPresent(Int.self, forKey: .focusScore)

        do {
            try self.init(
                id: id,
                projectCode: projectCode,
                workMode: workMode,
                start: start,
                end: end,
                focusScore: focusScore
            )
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid time entry: \(error.localizedDescription)",
                    underlyingError: error
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectCode, forKey: .projectCode)
        try container.encode(workMode, forKey: .workMode)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encodeIfPresent(focusScore, forKey: .focusScore)
    }
}

public struct ActiveTimer: Codable, Equatable, Sendable {
    public let projectCode: String
    public let workMode: WorkMode
    public let start: Date

    public init(projectCode: String, workMode: WorkMode, start: Date = Date()) throws {
        self.projectCode = try ProjectCode.normalize(projectCode)
        self.workMode = workMode
        self.start = start
    }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        max(0, date.timeIntervalSince(start))
    }

    private enum CodingKeys: String, CodingKey {
        case projectCode, workMode, start
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let projectCode = try container.decode(String.self, forKey: .projectCode)
        let workMode = try container.decode(WorkMode.self, forKey: .workMode)
        let start = try container.decode(Date.self, forKey: .start)

        do {
            try self.init(projectCode: projectCode, workMode: workMode, start: start)
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid active timer: \(error.localizedDescription)",
                    underlyingError: error
                )
            )
        }
    }
}
