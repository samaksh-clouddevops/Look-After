import XCTest
import Foundation
import LookAfterCore
@testable import LookAfterFeatures

final class PlanVariantBuilderTests: XCTestCase {

    func testBuildOfflineVariantsProducesThreeOptions() {
        let tasks = [
            LifeTask(title: "Deep work", priority: .high, estimatedMinutes: 60),
            LifeTask(title: "Email", priority: .medium, estimatedMinutes: 30),
            LifeTask(title: "Admin", priority: .low, estimatedMinutes: 15)
        ]
        let context = DayReplanContext(
            planningContext: PlanningConversationContext(
                userName: "Test",
                tasks: tasks,
                timelineItems: [],
                medications: [],
                availableMinutes: 120,
                energyPercent: 50
            ),
            completedTasks: []
        )
        let variants = PlanVariantBuilder.buildOfflineVariants(
            tasks: tasks,
            deferCandidates: [tasks[2]],
            context: context
        )
        XCTAssertGreaterThanOrEqual(variants.count, 2)
        XCTAssertTrue(variants.contains(where: \.recommended))
    }

    func testNegotiationMapsOptionToVariantID() {
        let variants = [
            PlanVariant(id: "a", label: "Plan A", summary: "A"),
            PlanVariant(id: "b", label: "Plan B", summary: "B")
        ]
        let negotiation = PlanVariantBuilder.negotiation(from: variants, question: "Pick:")
        XCTAssertEqual(negotiation.variantID(forOption: "Plan A"), "a")
        XCTAssertEqual(negotiation.variantID(forOption: "Plan B"), "b")
    }

    func testDayReplanResultEffectiveChangesUsesVariant() {
        let variant = PlanVariant(
            id: "v1",
            label: "Defer",
            summary: "Defer all",
            scheduleChanges: [DayReplanScheduleChange(taskID: "t1", deferToTomorrow: true, reason: "test")]
        )
        let result = DayReplanResult(
            summary: "Summary",
            scheduleChanges: [],
            planVariants: [variant],
            recommendedVariantID: "v1"
        )
        XCTAssertEqual(result.effectiveChanges().count, 1)
        XCTAssertEqual(result.effectiveChanges().first?.taskID, "t1")
    }
}
