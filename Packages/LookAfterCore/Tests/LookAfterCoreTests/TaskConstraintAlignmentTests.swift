import XCTest
@testable import LookAfterCore

final class TaskConstraintAlignmentTests: XCTestCase {
    func testFixedSchedulingModeAlignsToAnchoredForDailyRoutine() {
        var task = LifeTask(
            title: "Office Work",
            tags: ["daily-routine", "fixed"],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        task = TaskConstraintAlignment.align(task)
        XCTAssertEqual(task.timeConstraintValue, .anchored)
        XCTAssertFalse(task.isSchedulerMovable)
    }

    func testUserPlacedSkipsDriftRestore() {
        var task = LifeTask(
            title: "Dinner",
            scheduledTime: Date(),
            tags: ["daily-routine"],
            userId: "user-1"
        )
        TaskConstraintAlignment.markUserPlaced(&task)
        XCTAssertNotNil(task.userPlacedScheduleAt)
        XCTAssertTrue(TaskConstraintAlignment.isUserPlaced(task))
    }

    func testApplyUserSchedulingModeEditFlexibleToFixedSurvivesAlign() {
        var task = LifeTask(title: "Email", schedulingMode: .flexible, userId: "user-1")
        let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let end = start.addingTimeInterval(30 * 60)
        task.applyUserSchedulingModeEdit(.fixedTime, fixedStartTime: start, fixedEndTime: end)
        task = TaskConstraintAlignment.align(task)
        XCTAssertEqual(task.timeConstraintValue, .anchored)
        XCTAssertEqual(task.schedulingModeValue, .fixedTime)
        XCTAssertEqual(task.scheduledTime, start)
        XCTAssertEqual(task.scheduledEndTime, end)
    }

    func testApplyUserSchedulingModeEditFixedToFlexibleSurvivesAlign() {
        var task = LifeTask(
            title: "Standup",
            schedulingMode: .fixedTime,
            timeConstraint: .anchored,
            userId: "user-1"
        )
        task.scheduledTime = Date()
        task.scheduledEndTime = Date().addingTimeInterval(1800)
        task.applyUserSchedulingModeEdit(.flexible)
        task = TaskConstraintAlignment.align(task)
        XCTAssertEqual(task.timeConstraintValue, .flexible)
        XCTAssertEqual(task.schedulingModeValue, .flexible)
        XCTAssertNil(task.scheduledTime)
        XCTAssertNil(task.scheduledEndTime)
    }
}
