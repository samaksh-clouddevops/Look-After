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
