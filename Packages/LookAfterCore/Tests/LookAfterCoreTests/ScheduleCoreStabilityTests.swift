import XCTest
@testable import LookAfterCore

final class ScheduleCoreStabilityTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testCompletedGymSuppressesActiveRecurringFromResolver() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30)
        var completed = LifeTask(
            id: "gym-done",
            title: "Gym",
            status: .completed,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag],
            userId: "user-1"
        )
        completed.completedAt = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)

        let activeRecurring = LifeTask(
            id: "gym-recurring",
            title: "Gym",
            status: .pending,
            scheduledDate: day,
            tags: ["daily-routine"],
            userId: "user-1"
        )

        let all = [completed, activeRecurring]
        let resolved = TaskSeriesResolver.resolvedTasks(
            allTasks: all,
            options: TaskSeriesResolver.Options(day: day, includeProjections: false, includeCompleted: false, activeOnly: true),
            calendar: calendar
        )
        XCTAssertTrue(resolved.isEmpty)

        let stale = TaskSeriesResolver.staleActiveSeriesIDs(in: all, on: day, calendar: calendar)
        XCTAssertTrue(stale.contains("gym-recurring"))
    }

    func testMidnightOccurrenceNormalizedOnWrite() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let template = LifeTask(
            id: "tmpl",
            title: "Review notes",
            scheduledDate: day,
            scheduledTime: day,
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: day,
            calendar: calendar
        )
        XCTAssertNil(occurrence.scheduledTime)
        XCTAssertNil(occurrence.scheduledEndTime)
    }

    func testDisplayScheduleNeverShowsMidnightForPlaceholder() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let task = LifeTask(
            title: "Brush teeth",
            scheduledDate: day,
            scheduledTime: day,
            tags: ["daily-routine"],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        let display = TaskScheduleInterval.displaySchedule(for: task, on: day, calendar: calendar)
        XCTAssertEqual(display, .unslottedFlexible)
        XCTAssertFalse(display.scheduleLabel?.contains("12:00 AM") ?? true)
    }

    func testUserPlacedTaskCannotMoveInCascade() {
        var task = LifeTask(title: "Focus block", schedulingMode: .flexible, userId: "user-1")
        TaskConstraintAlignment.markUserPlaced(&task)
        XCTAssertFalse(ConflictResolutionCascade.canMove(task))
    }

    func testReconcilePolicyStableWhenNoOverlapOrUnslotted() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        var gym = LifeTask(
            title: "Gym",
            scheduledDate: day,
            scheduledTime: gymStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd,
            userId: "user-1"
        )
        gym.applyTimeConstraint(.anchored)

        let needsReplan = ReconcilePolicy.needsFullReplan(
            ReconcilePolicy.Input(tasks: [gym], day: day, model: nil, forceReplan: false),
            calendar: calendar
        )
        XCTAssertFalse(needsReplan)
    }

    func testTimelineShowsOneEventWhenCompletedAndActiveSameSeries() {
        let now = makeDate(year: 2026, month: 8, day: 7, hour: 21, minute: 0)
        let day = calendar.startOfDay(for: now)
        var completed = LifeTask(
            id: "gym-done",
            title: "Gym",
            status: .completed,
            scheduledDate: day,
            tags: [LifeModel.commitmentTaskTag],
            userId: "user-1"
        )
        completed.completedAt = now

        let events = LifeTimelinePresenter.build(
            tasks: [],
            completedToday: [completed],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(events.filter { $0.title == "Gym" }.count, 1)
        XCTAssertTrue(events.first(where: { $0.title == "Gym" })?.isCompleted == true)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
