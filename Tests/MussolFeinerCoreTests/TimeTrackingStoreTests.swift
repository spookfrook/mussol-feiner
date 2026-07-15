import Foundation
import XCTest
@testable import MussolFeinerCore

final class TimeTrackingStoreTests: XCTestCase {
    @MainActor
    func testStartingNewTimerCompletesOnlyActiveTimer() throws {
        let location = try temporaryStorageURL()
        let store = try TimeTrackingStore(storageURL: location)
        let start = Date(timeIntervalSince1970: 10_000)

        XCTAssertNil(try store.startTimer(projectCode: "one", workMode: .deepWork, at: start))
        let switchedEntry = try store.startTimer(
            projectCode: "two",
            workMode: .shallowWork,
            at: start.addingTimeInterval(3_600)
        )

        XCTAssertEqual(switchedEntry?.projectCode, "ONE")
        XCTAssertEqual(switchedEntry?.duration, 3_600)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.activeTimer?.projectCode, "TWO")

        let stoppedEntry = try store.stopTimer(
            at: start.addingTimeInterval(5_400),
            focusScore: 4
        )
        XCTAssertEqual(stoppedEntry?.duration, 1_800)
        XCTAssertEqual(stoppedEntry?.focusScore, 4)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertNil(store.activeTimer)
    }

    @MainActor
    func testActiveTimerAndEntriesSurviveRelaunch() throws {
        let location = try temporaryStorageURL()
        let start = Date(timeIntervalSince1970: 20_000)

        do {
            let store = try TimeTrackingStore(storageURL: location)
            _ = try store.addEntry(
                projectCode: "old",
                workMode: .passiveMeeting,
                start: start.addingTimeInterval(-600),
                end: start,
                focusScore: 2
            )
            _ = try store.startTimer(projectCode: "new", workMode: .activeMeeting, at: start)
        }

        let restored = try TimeTrackingStore(storageURL: location)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries.first?.projectCode, "OLD")
        XCTAssertEqual(restored.activeTimer?.projectCode, "NEW")
        XCTAssertEqual(restored.activeTimer?.start, start)

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: location.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: location.deletingLastPathComponent().path
        )
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    @MainActor
    func testManualEntryCRUDAndNormalization() throws {
        let store = try TimeTrackingStore(storageURL: temporaryStorageURL())
        let start = Date(timeIntervalSince1970: 30_000)
        let original = try store.addEntry(
            projectCode: "mix",
            workMode: .shallowWork,
            start: start,
            end: start.addingTimeInterval(600)
        )
        XCTAssertEqual(original.projectCode, "MIX")

        let updated = try store.updateEntry(
            id: original.id,
            projectCode: "hom",
            workMode: .deepWork,
            start: start,
            end: start.addingTimeInterval(1_200),
            focusScore: 5
        )
        XCTAssertEqual(store.entries, [updated])
        XCTAssertEqual(store.entries.first?.projectCode, "HOM")

        try store.delete(id: original.id)
        XCTAssertTrue(store.entries.isEmpty)

        let reloaded = try TimeTrackingStore(storageURL: store.storageURL)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    @MainActor
    func testFailedSwitchDoesNotReplaceActiveTimer() throws {
        let store = try TimeTrackingStore(storageURL: temporaryStorageURL())
        let start = Date(timeIntervalSince1970: 40_000)
        _ = try store.startTimer(projectCode: "one", workMode: .deepWork, at: start)

        XCTAssertThrowsError(
            try store.startTimer(
                projectCode: "two",
                workMode: .shallowWork,
                at: start.addingTimeInterval(-1)
            )
        )
        XCTAssertEqual(store.activeTimer?.projectCode, "ONE")
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testUpdateActiveTimerStartBackdatesAndPersists() throws {
        let location = try temporaryStorageURL()
        let store = try TimeTrackingStore(storageURL: location)
        let start = Date(timeIntervalSince1970: 50_000)
        _ = try store.startTimer(projectCode: "own", workMode: .deepWork, at: start)

        let backdated = start.addingTimeInterval(-300)
        try store.updateActiveTimerStart(to: backdated)

        XCTAssertEqual(store.activeTimer?.start, backdated)
        XCTAssertEqual(store.activeTimer?.elapsed(at: start), 300)
        XCTAssertTrue(store.entries.isEmpty)

        let restored = try TimeTrackingStore(storageURL: location)
        XCTAssertEqual(restored.activeTimer?.start, backdated)
        XCTAssertEqual(restored.activeTimer?.projectCode, "OWN")
    }

    @MainActor
    func testUpdateActiveTimerStartWithoutActiveTimerThrows() throws {
        let store = try TimeTrackingStore(storageURL: temporaryStorageURL())

        XCTAssertThrowsError(try store.updateActiveTimerStart(to: Date())) { error in
            XCTAssertEqual(error as? TimeTrackingValidationError, .noActiveTimer)
        }
    }

    private func temporaryStorageURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MussolFeinerTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("time-tracking.json")
    }
}
