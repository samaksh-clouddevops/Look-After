import XCTest
@testable import LookAfterCore

final class TaskSemanticProfileTests: XCTestCase {

    func testLevothyroxineProfileIsMorningRigidMedical() {
        let task = LifeTask(title: "Take Levothyroxine 50mcg", estimatedMinutes: 2)
        let profile = TaskSemanticProfileBuilder.build(from: task)

        XCTAssertEqual(profile.semanticType, .medication)
        XCTAssertEqual(profile.subtype, "Morning fasting medication")
        XCTAssertTrue(profile.schedulingConstraints.contains(.beforeBreakfast))
        XCTAssertTrue(profile.schedulingConstraints.contains(.neverEveningDose))
        XCTAssertTrue(profile.forbiddenTimeWindows.contains(.evening))
        XCTAssertEqual(profile.flexibility, .rigid)
        XCTAssertEqual(profile.consequenceOfDelay, .medicalRisk)
    }

    func testEveningMedicationBlockedByScheduler() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 1
        components.hour = 20
        let evening = Calendar.current.date(from: components)!

        let task = LifeTask(title: "Take Levothyroxine", estimatedMinutes: 2)
        let profile = TaskSemanticProfileBuilder.build(from: task)
        let context = TaskSemanticScheduler.Context(now: evening, energyScore: 0.7)

        let result = TaskSemanticScheduler.schedulability(profile: profile, context: context)
        XCTAssertFalse(result.isAllowed)
        XCTAssertNotNil(result.reason)
    }

    func testDeepCodingProfileRequiresFocusBlock() {
        let task = LifeTask(title: "Implement OAuth sign-in flow", difficulty: .hard, estimatedMinutes: 60)
        let profile = TaskSemanticProfileBuilder.build(from: task)

        XCTAssertEqual(profile.semanticType, .deepWork)
        XCTAssertEqual(profile.cognitiveRequirement, .deepFocus)
        XCTAssertTrue(profile.schedulingConstraints.contains(.requiresUninterruptedBlock))
        XCTAssertTrue(TaskSemanticScheduler.isDeepWorkCandidate(profile: profile))
    }

    func testDeepWorkBlockedAfterShortSleep() {
        let task = LifeTask(title: "Implement OAuth sign-in flow", difficulty: .hard, estimatedMinutes: 90)
        let profile = TaskSemanticProfileBuilder.build(from: task)
        XCTAssertTrue(TaskSemanticScheduler.isDeepWorkCandidate(profile: profile))
        let context = TaskSemanticScheduler.Context(
            energyScore: 0.7,
            sleepHours: 4.9,
            freeBlockMinutes: 120
        )
        let result = TaskSemanticScheduler.schedulability(profile: profile, context: context)
        XCTAssertFalse(result.isAllowed, "Deep work must not schedule after <6h sleep")
    }

    func testChronicDeferralSuggestsWeekdayShift() {
        XCTAssertNil(ChronicDeferralLearning.suggestedWeekdayOffset(deferralCount: 2))
        XCTAssertEqual(ChronicDeferralLearning.suggestedWeekdayOffset(deferralCount: 3), 1)
        XCTAssertEqual(ChronicDeferralLearning.suggestedWeekdayOffset(deferralCount: 6), 2)
        var task = LifeTask(title: "Tuesday gym", estimatedMinutes: 45)
        task.recurrence = .weekly
        let shifted = ChronicDeferralLearning.shiftedScheduleDate(for: task, deferralCount: 3)
        XCTAssertNotNil(shifted)
    }

    func testShoppingProfileIsFlexibleErrand() {
        let task = LifeTask(title: "Grocery shopping", estimatedMinutes: 45)
        let profile = TaskSemanticProfileBuilder.build(from: task)

        XCTAssertEqual(profile.semanticType, .errand)
        XCTAssertEqual(profile.flexibility, .high)
        XCTAssertTrue(profile.schedulingConstraints.contains(.requiresStoreOpen))
    }

    func testLLMMergePreservesMedicationSafety() {
        let task = LifeTask(title: "Take Levothyroxine", estimatedMinutes: 2)
        let deterministic = TaskSemanticProfileBuilder.build(from: task)
        var unsafeLLM = deterministic
        unsafeLLM.source = .llm
        unsafeLLM.preferredTimeWindows = [.evening]
        unsafeLLM.forbiddenTimeWindows = []
        unsafeLLM.flexibility = .high
        unsafeLLM.consequenceOfDelay = .low

        let merged = TaskSemanticProfileBuilder.merge(llm: unsafeLLM, deterministic: deterministic)
        XCTAssertEqual(merged.semanticType, .medication)
        XCTAssertTrue(merged.forbiddenTimeWindows.contains(.evening))
        XCTAssertEqual(merged.flexibility, .rigid)
        XCTAssertEqual(merged.consequenceOfDelay, .medicalRisk)
    }

    func testSemanticDecisionUsesProfileNotTitleHeuristicsAlone() {
        let task = LifeTask(
            title: "Morning pills",
            description: "Levothyroxine before food",
            estimatedMinutes: 2
        )
        var enriched = task
        enriched.semanticProfile = TaskSemanticProfileBuilder.build(from: task)

        let semantics = SemanticDecisionBuilder.from(task: enriched)
        XCTAssertEqual(semantics.object.kind, .medication)
    }
}
