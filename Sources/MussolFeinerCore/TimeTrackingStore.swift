import Combine
import Foundation

public enum TimeTrackingPersistenceError: Error, Equatable, LocalizedError, Sendable {
    case duplicateEntry(UUID)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .duplicateEntry:
            return "A time entry with that identifier already exists."
        case let .unsupportedSchemaVersion(version):
            return "The time tracking file uses unsupported schema version \(version)."
        }
    }
}

@MainActor
public final class TimeTrackingStore: ObservableObject {
    @Published public private(set) var entries: [TimeEntry]
    @Published public private(set) var activeTimer: ActiveTimer?

    public let storageURL: URL

    public nonisolated static var defaultStorageURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mussol Feiner", isDirectory: true)
            .appendingPathComponent("time-tracking.json", isDirectory: false)
    }

    private let fileManager: FileManager

    public init(
        storageURL: URL = TimeTrackingStore.defaultStorageURL,
        fileManager: FileManager = .default
    ) throws {
        self.storageURL = storageURL.standardizedFileURL
        self.fileManager = fileManager
        self.entries = []
        self.activeTimer = nil

        try prepareStorageDirectory()
        try reload()
    }

    /// Starts a timer. If another timer is active, it is completed at `date` first.
    /// The returned entry is that automatically completed timer, if one existed.
    @discardableResult
    public func startTimer(
        projectCode: String,
        workMode: WorkMode,
        at date: Date = Date()
    ) throws -> TimeEntry? {
        let nextTimer = try ActiveTimer(projectCode: projectCode, workMode: workMode, start: date)
        var completedEntry: TimeEntry?

        try mutateAndPersist {
            if let currentTimer = activeTimer {
                let entry = try TimeEntry(
                    projectCode: currentTimer.projectCode,
                    workMode: currentTimer.workMode,
                    start: currentTimer.start,
                    end: date
                )
                entries.append(entry)
                completedEntry = entry
            }
            activeTimer = nextTimer
            sortEntries()
        }

        return completedEntry
    }

    /// Completes the active timer. Entries without a focus score remain valid and are
    /// excluded from focus averages.
    @discardableResult
    public func stopTimer(
        at date: Date = Date(),
        focusScore: Int? = nil
    ) throws -> TimeEntry? {
        guard let timer = activeTimer else { return nil }

        let completedEntry = try TimeEntry(
            projectCode: timer.projectCode,
            workMode: timer.workMode,
            start: timer.start,
            end: date,
            focusScore: focusScore
        )

        try mutateAndPersist {
            entries.append(completedEntry)
            activeTimer = nil
            sortEntries()
        }

        return completedEntry
    }

    public func cancelTimer() throws {
        guard activeTimer != nil else { return }
        try mutateAndPersist {
            activeTimer = nil
        }
    }

    /// Moves the active timer's start, e.g. to credit work done before it was started
    /// or to correct its elapsed time while it runs.
    public func updateActiveTimerStart(to date: Date) throws {
        guard let timer = activeTimer else {
            throw TimeTrackingValidationError.noActiveTimer
        }

        let updated = try ActiveTimer(
            projectCode: timer.projectCode,
            workMode: timer.workMode,
            start: date
        )
        try mutateAndPersist {
            activeTimer = updated
        }
    }

    @discardableResult
    public func addEntry(
        projectCode: String,
        workMode: WorkMode,
        start: Date,
        end: Date,
        focusScore: Int? = nil
    ) throws -> TimeEntry {
        let entry = try TimeEntry(
            projectCode: projectCode,
            workMode: workMode,
            start: start,
            end: end,
            focusScore: focusScore
        )
        try add(entry)
        return entry
    }

    public func add(_ entry: TimeEntry) throws {
        guard !entries.contains(where: { $0.id == entry.id }) else {
            throw TimeTrackingPersistenceError.duplicateEntry(entry.id)
        }

        try mutateAndPersist {
            entries.append(entry)
            sortEntries()
        }
    }

    public func update(_ entry: TimeEntry) throws {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            throw TimeTrackingValidationError.entryNotFound(entry.id)
        }

        try mutateAndPersist {
            entries[index] = entry
            sortEntries()
        }
    }

    @discardableResult
    public func updateEntry(
        id: UUID,
        projectCode: String,
        workMode: WorkMode,
        start: Date,
        end: Date,
        focusScore: Int? = nil
    ) throws -> TimeEntry {
        let replacement = try TimeEntry(
            id: id,
            projectCode: projectCode,
            workMode: workMode,
            start: start,
            end: end,
            focusScore: focusScore
        )
        try update(replacement)
        return replacement
    }

    public func delete(id: UUID) throws {
        guard entries.contains(where: { $0.id == id }) else {
            throw TimeTrackingValidationError.entryNotFound(id)
        }

        try mutateAndPersist {
            entries.removeAll(where: { $0.id == id })
        }
    }

    /// Reloads both completed entries and the active timer from disk.
    public func reload() throws {
        try prepareStorageDirectory()
        guard fileManager.fileExists(atPath: storageURL.path) else {
            entries = []
            activeTimer = nil
            return
        }

        let data = try Data(contentsOf: storageURL)
        let snapshot = try Self.persistenceDecoder.decode(StorageSnapshot.self, from: data)
        guard snapshot.schemaVersion == StorageSnapshot.currentSchemaVersion else {
            throw TimeTrackingPersistenceError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }

        entries = snapshot.entries.sorted(by: Self.entrySort)
        activeTimer = snapshot.activeTimer
        applyPrivateFilePermissions()
    }

    private func mutateAndPersist(_ mutation: () throws -> Void) throws {
        let oldEntries = entries
        let oldActiveTimer = activeTimer

        do {
            try mutation()
            try persist()
        } catch {
            entries = oldEntries
            activeTimer = oldActiveTimer
            throw error
        }
    }

    private func persist() throws {
        try prepareStorageDirectory()
        let snapshot = StorageSnapshot(entries: entries, activeTimer: activeTimer)
        let data = try Self.persistenceEncoder.encode(snapshot)
        try data.write(to: storageURL, options: .atomic)
        applyPrivateFilePermissions()
    }

    private func prepareStorageDirectory() throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directoryURL.path
        )
    }

    private func applyPrivateFilePermissions() {
        try? fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: storageURL.path
        )
    }

    private func sortEntries() {
        entries.sort(by: Self.entrySort)
    }

    private static func entrySort(_ lhs: TimeEntry, _ rhs: TimeEntry) -> Bool {
        if lhs.start != rhs.start { return lhs.start > rhs.start }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static let persistenceEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let persistenceDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

private struct StorageSnapshot: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let entries: [TimeEntry]
    let activeTimer: ActiveTimer?

    init(entries: [TimeEntry], activeTimer: ActiveTimer?) {
        self.schemaVersion = Self.currentSchemaVersion
        self.entries = entries
        self.activeTimer = activeTimer
    }
}
