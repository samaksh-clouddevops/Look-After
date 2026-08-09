import XCTest
@testable import LookAfterCore

final class MidnightScheduleRepairTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testOrphanMidnightWithoutScheduledDateNeverShowsWindow() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        var task = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: day,
            tags: [LifeModel.commitmentTaskTag],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        task.applyTimeConstraint(.anchored)

        let display = TaskScheduleInterval.displaySchedule(for: task, on: day, calendar: calendar)
        XCTAssertEqual(display, .unslottedFlexible)

        let now = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        let events = LifeTimelinePresenter.build(
            tasks: [task],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )
        let event = events.first(where: { $0.title == "Gym" })
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.subtitle, "Flexible today")
        XCTAssertFalse(event!.subtitle.contains("12:00 AM"))
    }

    func testMidnightClockIsAlwaysPlaceholderEvenWhenUserPlaced() {
        let day = calendar.startOfDay(for: Date())
        var task = LifeTask(
            id: "t1",
            title: "Gym",
            scheduledDate: day,
            scheduledTime: day,
            userId: "u"
        )
        XCTAssertTrue(TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar))

        TaskConstraintAlignment.markUserPlaced(&task)
        XCTAssertTrue(TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar))

        ScheduleNormalization.normalizeFields(&task, calendar: calendar)
        XCTAssertNil(task.scheduledTime)
        XCTAssertNil(task.userPlacedScheduleAt)
    }

    func testShouldRestoreMidnightPlaceholder() {
        let day = calendar.startOfDay(for: Date())
        let markdown = """
        ### Gym
        **6:30 PM – 8:00 PM**
        """
        let model = LifeModelValidator.compileLocally(from: markdown)
        let task = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: day,
            tags: [LifeModel.commitmentTaskTag, model.commitmentID(for: "Gym")],
            schedulingMode: .fixedTime,
            userId: "u"
        )
        let anchor = RoutineScheduleAnchorResolver.resolve(for: task, on: day, model: model, calendar: calendar)
        XCTAssertNotNil(anchor)
        XCTAssertTrue(
            RoutineScheduleAnchorResolver.shouldRestore(task: task, anchor: anchor!, calendar: calendar)
        )
    }

    func testKeywordAnchorMatchesVocalPracticeToCreativeBlock() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        let markdown = """
        ### Creative Deep Work
        **7:00 PM – 9:00 PM**
        """
        let model = LifeModelValidator.compileLocally(from: markdown)
        let task = LifeTask(title: "Vocal Practice", estimatedMinutes: 30, userId: "u")
        let anchor = try XCTUnwrap(
            RoutineScheduleAnchorResolver.resolve(for: task, on: day, model: model, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: anchor.start), 19)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
