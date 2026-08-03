import XCTest
@testable import LookAfterCore

final class ExecutiveRecommendationEngineTests: XCTestCase {

    private var evening: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 1
        components.hour = 21
        components.minute = 52
        return Calendar.current.date(from: components)!
    }

    func testEveningStaleMorningWorkFallsBackToEveningPlan() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 2
        components.hour = 23
        let lateEvening = Calendar.current.date(from: components)!

        let dayStart = Calendar.current.startOfDay(for: lateEvening)
        let workStart = Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: dayStart)!
        let work = LifeTask(
            title: "Work",
            lifeArea: .work,
            estimatedMinutes: 51,
            scheduledDate: dayStart,
            scheduledTime: workStart,
            schedulingMode: .fixedTime
        )
        let musicStart = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: dayStart)!
        let musicEnd = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: dayStart)!
        let music = LifeTask(
            title: "Music production",
            lifeArea: .creativity,
            estimatedMinutes: 90,
            scheduledDate: dayStart,
            scheduledTime: musicStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: musicEnd
        )

        let snapshot = LifeContextSnapshot(currentEnergy: 0.6, availableTimeMinutes: 90, currentMission: work)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: work,
            snapshot: snapshot,
            tasks: [work, music],
            now: lateEvening
        ))

        XCTAssertNotNil(output)
        XCTAssertEqual(output?.taskID, music.id)
    }

    func testEveningThyroidMedicationSkipsToAlternateOrEveningPlan() {
        let thyroid = LifeTask(
            title: "Take Thyroid Medication",
            steps: [TaskStep(title: "Walk to where your thyroid medication is kept", isCompleted: false)],
            estimatedMinutes: 5,
            semanticProfile: TaskSemanticProfileBuilder.build(from: LifeTask(
                title: "Take levothyroxine",
                description: "Morning thyroid medication before breakfast"
            ))
        )
        let work = LifeTask(
            title: "Deep Work Block 1",
            description: "Review Azure deployment",
            estimatedMinutes: 30,
            semanticProfile: TaskSemanticProfile(semanticType: .deepWork)
        )

        let snapshot = LifeContextSnapshot(currentEnergy: 0.6, availableTimeMinutes: 90)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: thyroid,
            snapshot: snapshot,
            tasks: [thyroid, work],
            now: evening
        ))

        XCTAssertNotNil(output)
        XCTAssertFalse(output?.headline.lowercased().contains("walk to") == true)
        XCTAssertFalse(output?.headline.lowercased().contains("missed") == true)
    }

    func testGymPrepRecommendationBeforeSession() {
        var gymTime = evening
        gymTime = Calendar.current.date(byAdding: .minute, value: 25, to: evening)!

        let task = LifeTask(
            title: "Gym",
            estimatedMinutes: 60,
            scheduledTime: gymTime,
            semanticProfile: TaskSemanticProfile(semanticType: .physicalActivity)
        )

        let snapshot = LifeContextSnapshot(currentEnergy: 0.7, availableTimeMinutes: 120)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: task,
            snapshot: snapshot,
            now: evening
        ))

        XCTAssertTrue(
            output?.headline == "Put on workout clothes" || output?.headline == "Fill your water bottle",
            "Expected prep headline, got \(output?.headline ?? "nil")"
        )
        XCTAssertEqual(output?.buttonLabel, "I'm ready")
        XCTAssertTrue(output?.isPreparation == true)
    }

    func testHeadlineAndButtonAreDistinct() {
        let task = LifeTask(
            title: "Deep Work Block 1",
            description: "Review Azure deployment",
            estimatedMinutes: 30,
            semanticProfile: TaskSemanticProfile(semanticType: .deepWork)
        )
        let snapshot = LifeContextSnapshot(currentEnergy: 0.75, availableTimeMinutes: 120)
        let output = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: task,
            snapshot: snapshot,
            now: evening
        ))

        XCTAssertEqual(output?.headline, "Review Azure deployment")
        XCTAssertEqual(output?.buttonLabel, "Start now")
        XCTAssertNotEqual(output?.headline, output?.buttonLabel)
    }

    func testMedicationStepNotUsedAsObjective() {
        let task = LifeTask(
            title: "Thyroid medication",
            description: "Take levothyroxine on empty stomach",
            steps: [TaskStep(title: "Walk to where your thyroid medication is kept", isCompleted: false)],
            semanticProfile: TaskSemanticProfile(semanticType: .medication, subtype: "Morning fasting medication")
        )
        let context = HeroObjectiveContextBuilder.from(task: task)
        let headline = HeroObjectiveResolver.resolveHeadline(from: context)

        XCTAssertFalse(headline.lowercased().contains("walk to"))
        XCTAssertTrue(headline.lowercased().contains("levothyroxine") || headline.lowercased().contains("medication"))
    }
}
