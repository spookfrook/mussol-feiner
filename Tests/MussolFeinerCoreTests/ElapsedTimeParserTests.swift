import XCTest
@testable import MussolFeinerCore

final class ElapsedTimeParserTests: XCTestCase {
    func testBareNumberMeansMinutes() {
        XCTAssertEqual(ElapsedTimeParser.parse("45"), 2_700)
        XCTAssertEqual(ElapsedTimeParser.parse("0"), 0)
        XCTAssertEqual(ElapsedTimeParser.parse("1.5"), 90)
        XCTAssertEqual(ElapsedTimeParser.parse("  45  "), 2_700)
    }

    func testUnitNotation() {
        XCTAssertEqual(ElapsedTimeParser.parse("45m"), 2_700)
        XCTAssertEqual(ElapsedTimeParser.parse("45 min"), 2_700)
        XCTAssertEqual(ElapsedTimeParser.parse("2 hours"), 7_200)
        XCTAssertEqual(ElapsedTimeParser.parse("90s"), 90)
        XCTAssertEqual(ElapsedTimeParser.parse("1.5h"), 5_400)
        XCTAssertEqual(ElapsedTimeParser.parse("0,5h"), 1_800)
        XCTAssertEqual(ElapsedTimeParser.parse("1H 30M"), 5_400)
    }

    func testCompoundUnitNotation() {
        XCTAssertEqual(ElapsedTimeParser.parse("1h 30m"), 5_400)
        XCTAssertEqual(ElapsedTimeParser.parse("1h30m"), 5_400)
        XCTAssertEqual(ElapsedTimeParser.parse("1h30"), 5_400)
        XCTAssertEqual(ElapsedTimeParser.parse("2h 15m 10s"), 8_110)
        XCTAssertEqual(ElapsedTimeParser.parse("10m 30"), 630)
        XCTAssertEqual(ElapsedTimeParser.parse("5h30m10"), 19_810)
    }

    func testClockNotation() {
        XCTAssertEqual(ElapsedTimeParser.parse("1:30"), 5_400)
        XCTAssertEqual(ElapsedTimeParser.parse("0:05"), 300)
        XCTAssertEqual(ElapsedTimeParser.parse("01:30:00"), 5_400)
        XCTAssertEqual(ElapsedTimeParser.parse("00:05:32"), 332)
        XCTAssertEqual(ElapsedTimeParser.parse("23:59:59"), 86_399)
        XCTAssertEqual(ElapsedTimeParser.parse("24:00"), 86_400)
    }

    func testRejectsInvalidInput() {
        let invalid = [
            "", "   ", "abc", "5x", "-5", "-5m", "+5",
            "30 1h", "5m 1h", "45 5m", "1..5h", ".5h", "5.",
            "1:99", "1:10:75", "1:2:3:4", "5:", ":30", "1.5:00",
            "25h", "24:01", "1441", "999999999999999999999m",
        ]
        for input in invalid {
            XCTAssertNil(ElapsedTimeParser.parse(input), "Expected \"\(input)\" to be rejected")
        }
    }

    func testAcceptsExactlyTheMaximum() {
        XCTAssertEqual(ElapsedTimeParser.parse("24h"), ElapsedTimeParser.maximumInterval)
        XCTAssertEqual(ElapsedTimeParser.parse("1440"), ElapsedTimeParser.maximumInterval)
    }
}
