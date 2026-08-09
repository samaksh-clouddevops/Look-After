import XCTest
@testable import LookAfterCore

final class CascadeHistoryDedupTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private var day: Date {
        calendar.date(from: DateComponents(year: 2024, month: 7, day: 7, hour: 12))!
    }

    func testCompactCollapsesDuplicateShiftOnSameDay() {
        let first = CascadeActionRecord(
            kind: .shiftedLater,
            timestamp: day,
            durationMinutes: 30,
            taskID: "task-a"
        )
        let duplicate = CascadeActionRecord(
            kind: .shiftedLater,
            timestamp: day.addingTimeInterval(120),
            durationMinutes: 45,
            taskID: "task-a"
        )
        let otherTask = CascadeActionRecord(
            kind: .shiftedLater,
            timestamp: day,
            durationMinutes: 15,
            taskID: "task-b"
        )

        let compacted = CascadeHistoryDedup.compact([duplicate, first, otherTask], calendar: calendar)

        XCTAssertEqual(compacted.count, 2)
        XCTAssertEqual(compacted.filter { $0.taskID == "task-a" }.count, 1)
        XCTAssertEqual(compacted.first { $0.taskID == "task-a" }?.durationMinutes, 30)
    }

    func testMergeKeepsOneSabotageAuctionPerDay() {
        let first = CascadeActionRecord(kind: .sabotageAuction, timestamp: day, durationMinutes: 90)
        let duplicate = CascadeActionRecord(
            kind: .sabotageAuction,
            timestamp: day.addingTimeInterval(300),
            durationMinutes: 60
        )

        let merged = CascadeHistoryDedup.merge(incoming: [duplicate], into: [first], calendar: calendar)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].durationMinutes, 90)
    }

    func testDifferentDaysAreNotDeduped() {
        let dayOne = CascadeActionRecord(
            kind: .shiftedLater,
            timestamp: day,
            durationMinutes: 30,
            taskID: "task-a"
        )
        let dayTwo = CascadeActionRecord(
            kind: .shiftedLater,
            timestamp: day.addingTimeInterval(86_400),
            durationMinutes: 30,
            taskID: "task-a"
        )

        let compacted = CascadeHistoryDedup.compact([dayOne, dayTwo], calendar: calendar)

        XCTAssertEqual(compacted.count, 2)
    }
}
