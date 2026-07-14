import Foundation
import XCTest
@testable import MussolFeinerCore

final class ExportTests: XCTestCase {
    func testJSONExportRoundTripsAsPortableBackup() throws {
        let entries = try fixtures()
        let data = try DataExporter.data(for: entries, format: .json)
        let decoded = try DataExporter.decodeJSON(data)

        XCTAssertEqual(decoded, entries.sorted { $0.start < $1.start })
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testRangeExportSelectsOnlyOverlappingEntries() throws {
        let entries = try fixtures()
        let range = DateInterval(
            start: Date(timeIntervalSince1970: 1_500),
            end: Date(timeIntervalSince1970: 2_500)
        )
        let selected = DataExporter.selected(entries, scope: .range(range))

        XCTAssertEqual(selected.map(\.projectCode), ["ONE", "TWO"])
        XCTAssertEqual(selected.map(\.duration), [500, 500])
        XCTAssertEqual(selected.first?.start, range.start)
        XCTAssertEqual(selected.last?.end, range.end)
    }

    func testCSVAndMarkdownEscaping() {
        XCTAssertEqual(DataExporter.csvEscape("plain"), "plain")
        XCTAssertEqual(
            DataExporter.csvEscape("one, \"two\"\nthree"),
            "\"one, \"\"two\"\"\nthree\""
        )
        XCTAssertEqual(
            DataExporter.markdownEscape("a|b\\c\nd"),
            "a\\|b\\\\c<br>d"
        )
    }

    func testCSVUsesBlankFocusAndRFC4180LineEndings() throws {
        let csv = try DataExporter.string(
            for: [fixtures()[0]],
            format: .csv
        )

        XCTAssertTrue(csv.hasSuffix("\r\n"))
        XCTAssertTrue(csv.contains("Deep Work,DPW"))
        XCTAssertTrue(csv.split(separator: "\n").last?.hasSuffix(",\r") == true)
    }

    func testAtomicExportHasOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MussolFeinerExportTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("backup.json")

        try DataExporter.write(
            entries: fixtures(),
            format: .json,
            to: destination
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    private func fixtures() throws -> [TimeEntry] {
        [
            try TimeEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                projectCode: "ONE",
                workMode: .deepWork,
                start: Date(timeIntervalSince1970: 1_000.125),
                end: Date(timeIntervalSince1970: 2_000)
            ),
            try TimeEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                projectCode: "TWO",
                workMode: .activeMeeting,
                start: Date(timeIntervalSince1970: 2_000),
                end: Date(timeIntervalSince1970: 3_000),
                focusScore: 4
            ),
            try TimeEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                projectCode: "TRE",
                workMode: .shallowWork,
                start: Date(timeIntervalSince1970: 3_000),
                end: Date(timeIntervalSince1970: 4_000),
                focusScore: 2
            )
        ]
    }
}
