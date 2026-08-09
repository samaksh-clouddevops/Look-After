import XCTest
@testable import LookAfterCore

final class PlanningTimeParserTests: XCTestCase {
    func testParsesThreePM() {
        let parsed = PlanningTimeParser.parseHourMinute(from: "move email to 3pm")
        XCTAssertEqual(parsed?.hour, 15)
        XCTAssertEqual(parsed?.minute, 0)
    }

    func testParsesTwentyFourHourClock() {
        let parsed = PlanningTimeParser.parseHourMinute(from: "reschedule to 14:30")
        XCTAssertEqual(parsed?.hour, 14)
        XCTAssertEqual(parsed?.minute, 30)
    }

    func testParsesAtThree() {
        let parsed = PlanningTimeParser.parseHourMinute(from: "shift standup at 3")
        XCTAssertEqual(parsed?.hour, 3)
        XCTAssertEqual(parsed?.minute, 0)
    }

    func testReturnsNilForNoTime() {
        XCTAssertNil(PlanningTimeParser.parseHourMinute(from: "defer email to tomorrow"))
    }
}
