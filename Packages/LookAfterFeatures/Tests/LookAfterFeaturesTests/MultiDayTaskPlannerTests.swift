import XCTest
@testable import LookAfterCore
@testable import LookAfterFeatures

final class MultiDayTaskPlannerTests: XCTestCase {

    @MainActor
    func testPlanCreatesParentAndSlices() {
        let draft = MultiDayPlanDraft(
            title: "Finish quarterly report",
            dayCount: 3,
            lifeArea: .work,
            slices: [
                MultiDaySliceDraft(dayIndex: 0, title: "Gather data", estimatedMinutes: 45, windowLabel: "Office"),
                MultiDaySliceDraft(dayIndex: 1, title: "Draft outline", estimatedMinutes: 45, windowLabel: "Office"),
                MultiDaySliceDraft(dayIndex: 2, title: "Final review", estimatedMinutes: 30, windowLabel: "Office")
            ],
            reasoning: "Three focused office sessions."
        )

        let plan = MultiDayTaskPlanner.plan(from: draft, userId: "test-user")

        XCTAssertTrue(MultiDayTaskTags.isRoot(plan.parent))
        XCTAssertNil(plan.parent.scheduledTime)
        XCTAssertEqual(plan.slices.count, 3)
        for slice in plan.slices {
            XCTAssertTrue(MultiDayTaskTags.isSlice(slice))
            XCTAssertEqual(slice.parentTaskId, plan.parent.id)
            XCTAssertNotNil(slice.scheduledDate)
        }
    }

    @MainActor
    func testOfflinePlanClampsDayCount() {
        let plan = MultiDayTaskPlanner.plan(
            title: "Big goal",
            dayCount: 1,
            lifeArea: .work,
            userId: "test-user"
        )
        XCTAssertGreaterThanOrEqual(plan.slices.count, 2)
    }

    @MainActor
    func testSliceAvoidsTimeOnlyOccupiedClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 8))!
        let clock = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 9))!
        let clockEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 10))!
        let occupied = LifeTask(
            id: "standup-time-only",
            title: "Standup",
            estimatedMinutes: 60,
            scheduledTime: clock,
            schedulingMode: .fixedTime,
            scheduledEndTime: clockEnd,
            userId: "test-user"
        )
        let draft = MultiDayPlanDraft(
            title: "Finish quarterly report",
            dayCount: 2,
            lifeArea: .work,
            slices: [
                MultiDaySliceDraft(dayIndex: 0, title: "Gather data", estimatedMinutes: 30, windowLabel: "Office"),
                MultiDaySliceDraft(dayIndex: 1, title: "Draft outline", estimatedMinutes: 30, windowLabel: "Office")
            ],
            reasoning: "Two office sessions."
        )

        let plan = MultiDayTaskPlanner.plan(
            from: draft,
            userId: "test-user",
            existingTasks: [occupied],
            startDate: start
        )
        let first = plan.slices.first { $0.title == "Gather data" }

        XCTAssertNotNil(first?.scheduledTime)
        XCTAssertGreaterThanOrEqual(first?.scheduledTime ?? start, clockEnd)
    }


    @MainActor
    func testCreativePlanCreatesProject() {
        let draft = MultiDayPlanDraft(
            title: "Album prep",
            dayCount: 4,
            lifeArea: .creativity,
            slices: (0..<4).map { MultiDaySliceDraft(dayIndex: $0, title: "Day \($0 + 1)", estimatedMinutes: 60) }
        )
        let plan = MultiDayTaskPlanner.plan(from: draft, userId: "test-user")
        XCTAssertNotNil(plan.project)
        XCTAssertEqual(plan.project?.dayCount, 4)
        XCTAssertEqual(plan.project?.parentTaskId, plan.parent.id)
    }
}
