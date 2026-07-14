import Foundation
import XCTest
@testable import MussolFeinerCore

final class ModelsTests: XCTestCase {
    func testProjectCodeNormalization() throws {
        XCTAssertEqual(try ProjectCode.normalize("  abc\n"), "ABC")
        XCTAssertEqual(try ProjectCode.normalize("xYz"), "XYZ")
    }

    func testProjectCodeRequiresExactlyThreeLetters() {
        XCTAssertThrowsError(try ProjectCode.normalize("AB"))
        XCTAssertThrowsError(try ProjectCode.normalize("ABCD"))
        XCTAssertThrowsError(try ProjectCode.normalize("A1C"))
        XCTAssertThrowsError(try ProjectCode.normalize("A C"))
    }

    func testWorkModeMetadata() {
        XCTAssertEqual(WorkMode.deepWork.code, "DPW")
        XCTAssertEqual(WorkMode.deepWork.label, "Deep Work")
        XCTAssertEqual(WorkMode.shallowWork.code, "SHW")
        XCTAssertEqual(WorkMode.activeMeeting.code, "AMT")
        XCTAssertEqual(WorkMode.passiveMeeting.code, "PMT")
        XCTAssertTrue(WorkMode.allCases.allSatisfy { $0.defaultColorHex.hasPrefix("#") })
    }

    func testTimeEntryValidatesAndComputesDuration() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let entry = try TimeEntry(
            projectCode: "app",
            workMode: .deepWork,
            start: start,
            end: start.addingTimeInterval(90),
            focusScore: 5
        )

        XCTAssertEqual(entry.projectCode, "APP")
        XCTAssertEqual(entry.duration, 90)
        XCTAssertEqual(entry.focusScore, 5)
        XCTAssertThrowsError(
            try TimeEntry(
                projectCode: "APP",
                workMode: .deepWork,
                start: start,
                end: start.addingTimeInterval(-1)
            )
        )
        XCTAssertThrowsError(
            try TimeEntry(
                projectCode: "APP",
                workMode: .deepWork,
                start: start,
                end: start,
                focusScore: 6
            )
        )
    }
}
