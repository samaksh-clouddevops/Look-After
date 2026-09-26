import XCTest
@testable import LookAfterCore

final class DayPlateBuilderTests: XCTestCase {
    func testInputsSplitActiveCompletedAndTemplates() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents(year: 2026, month: 9, day: 14, hour: 12)
        let now = calendar.date(from: components)!
        let dayStart = calendar.startOfDay(for: now)

        let active = LifeTask(
            id: "a1",
            title: "Deep work",
            status: .pending,
            scheduledDate: dayStart,
            scheduledTime: now,
            userId: "u1"
        )
        var completed = LifeTask(
            id: "c1",
            title: "Lunch",
            status: .completed,
            scheduledDate: dayStart,
            userId: "u1"
        )
        completed.completedAt = now.addingTimeInterval(-3600)
        let template = LifeTask(
            id: "t1",
            title: "Dinner",
            status: .pending,
            tags: ["routine-block:dinner-1"],
            recurrence: .daily,
            userId: "u1",
            isRecurrenceTemplate: true
        )

        let plate = DayPlateBuilder.inputs(from: [active, completed, template], now: now, calendar: calendar)
        XCTAssertEqual(plate.tasks.map(\.id), ["a1"])
        XCTAssertEqual(plate.completedToday.map(\.id), ["c1"])
        XCTAssertEqual(plate.recurrenceTemplates.map(\.id), ["t1"])
    }

    func testTimeOnlyFutureCompletionDoesNotLandOnTodayRail() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
        let tomorrowClock = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 21, minute: 30))!
        var completed = LifeTask(
            id: "future-clock",
            title: "Dinner",
            status: .completed,
            scheduledTime: tomorrowClock,
            userId: "u1"
        )
        completed.completedAt = nil

        let plate = DayPlateBuilder.inputs(from: [completed], now: now, calendar: calendar)
        XCTAssertFalse(plate.completedToday.contains(where: { $0.id == "future-clock" }))
    }

    func testSeriesKeyPrefersRoutineBlockAndCommitmentTags() {
        let routine = LifeTask(
            id: "r1",
            title: "Dinner",
            status: .pending,
            tags: ["routine-block:abc"],
            userId: "u1"
        )
        let commitment = LifeTask(
            id: "c1",
            title: "Dinner",
            status: .pending,
            tags: [LifeModel.commitmentTaskTag, "life-commitment:dinner"],
            userId: "u1"
        )
        XCTAssertEqual(TaskScheduleQuery.seriesKey(for: routine), "series|routine-block:abc")
        XCTAssertEqual(TaskScheduleQuery.seriesKey(for: commitment), "series|life-commitment:dinner")
        XCTAssertNotEqual(
            TaskScheduleQuery.seriesKey(for: routine),
            TaskScheduleQuery.seriesKey(for: commitment)
        )
    }

    func testScheduledTaskCountForwardsQueriedDayAsReferenceDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let queriedDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 9))!
        let dayStart = calendar.startOfDay(for: queriedDay)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: dayStart)!
        let carryForward = LifeTask(
            id: "carry",
            title: "Pay rent",
            status: .pending,
            estimatedMinutes: 15,
            scheduledDate: yesterday,
            userId: "u1"
        )

        XCTAssertEqual(
            DayPlateBuilder.scheduledTaskCount(from: [carryForward], day: queriedDay, calendar: calendar),
            1
        )
    }
}
