import XCTest
@testable import LookAfterCore

final class ScheduleOverlapInvariantTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testMisAnchoredMealShiftsAfterGym() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        let dinnerStart = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 0)
        let dinnerEnd = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 45)

        var gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag, "life-commitment:gym"],
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd
        )
        gym.applyTimeConstraint(.anchored)

        var dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: dinnerStart,
            tags: ["onboarding", "fixed", "daily-routine"],
            recurrence: .daily,
            schedulingMode: .fixedTime,
            scheduledEndTime: dinnerEnd
        )
        dinner.applyTimeConstraint(.anchored)

        let result = DayScheduleReconciler.reconcile(
            tasks: [gym, dinner],
            on: day,
            calendar: calendar
        )

        let updatedDinner = result.tasks.first { $0.title == "Dinner" }
        XCTAssertNotNil(updatedDinner)
        XCTAssertEqual(updatedDinner?.timeConstraintValue, .flexible)
        let dinnerWindow = TaskScheduleInterval.window(for: updatedDinner!, on: day, calendar: calendar)
        XCTAssertNotNil(dinnerWindow)
        XCTAssertGreaterThanOrEqual(dinnerWindow!.start, gymEnd)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(result.tasks, on: day, calendar: calendar))
    }

    func testDriftSnapOverlapRepairedByReconcile() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        let dinnerStart = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 0)
        let dinnerEnd = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 45)

        var gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag],
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd
        )
        gym.applyTimeConstraint(.anchored)

        var dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: dinnerStart,
            tags: ["daily-routine"],
            schedulingMode: .fixedTime,
            scheduledEndTime: dinnerEnd
        )
        dinner = TaskConstraintAlignment.align(dinner)

        XCTAssertTrue(
            DayScheduleReconciler.hasOverlap([gym, dinner], on: day, calendar: calendar)
        )

        let result = DayScheduleReconciler.reconcile(tasks: [gym, dinner], on: day, calendar: calendar)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(result.tasks, on: day, calendar: calendar))
        let updatedDinner = result.tasks.first { $0.title == "Dinner" }
        let dinnerWindow = TaskScheduleInterval.window(for: updatedDinner!, on: day, calendar: calendar)
        XCTAssertGreaterThanOrEqual(dinnerWindow!.start, gymEnd)
    }

    func testScheduledActiveTasksUsesConcreteWindow() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30)
        let task = LifeTask(
            title: "Gym",
            scheduledDate: day,
            scheduledTime: gymStart,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        let pool = TaskScheduleQuery.scheduledActiveTasks(from: [task], on: day, calendar: calendar)
        XCTAssertEqual(pool.count, 1)
    }

    func testPlannerApplyPersistsSmallShiftWhenOverlapRemoved() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let ten = makeDate(year: 2026, month: 8, day: 7, hour: 10, minute: 0)
        let tenTen = makeDate(year: 2026, month: 8, day: 7, hour: 10, minute: 10)
        let tenTwenty = makeDate(year: 2026, month: 8, day: 7, hour: 10, minute: 20)

        var left = LifeTask(
            id: "left",
            title: "Write",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: ten,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        left.applyTimeConstraint(.flexible)
        var right = LifeTask(
            id: "right",
            title: "Review",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: ten,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        right.applyTimeConstraint(.flexible)

        let plan = DaySchedulePlanner.PlanResult(
            slots: [
                .init(taskID: "left", start: ten, end: tenTen),
                .init(taskID: "right", start: tenTen, end: tenTwenty),
            ],
            changedTaskIDs: ["right"]
        )
        let applied = DaySchedulePlanner.apply(plan: plan, to: [left, right], on: day, calendar: calendar)
        XCTAssertTrue(applied.changedIDs.contains("right"))
        let updatedRight = applied.tasks.first { $0.id == "right" }
        XCTAssertEqual(updatedRight?.scheduledTime, tenTen)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(applied.tasks, on: day, calendar: calendar))
    }

    func testUserPlacedMealStillShiftsAfterGym() {
        let day = makeDate(year: 2026, month: 8, day: 7)
        let gymStart = makeDate(year: 2026, month: 8, day: 7, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        let dinnerStart = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 0)
        let dinnerEnd = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 45)

        var gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag],
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd
        )
        gym.applyTimeConstraint(.anchored)

        var dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: dinnerStart,
            tags: ["daily-routine"],
            schedulingMode: .fixedTime,
            scheduledEndTime: dinnerEnd,
            userPlacedScheduleAt: Date()
        )
        dinner.applyTimeConstraint(.flexible)

        XCTAssertTrue(ConflictResolutionCascade.canMove(dinner))
        let result = DayScheduleReconciler.reconcile(tasks: [gym, dinner], on: day, calendar: calendar)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(result.tasks, on: day, calendar: calendar))
        let updatedDinner = result.tasks.first { $0.title == "Dinner" }
        let dinnerWindow = TaskScheduleInterval.window(for: updatedDinner!, on: day, calendar: calendar)
        XCTAssertGreaterThanOrEqual(dinnerWindow!.start, gymEnd)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
