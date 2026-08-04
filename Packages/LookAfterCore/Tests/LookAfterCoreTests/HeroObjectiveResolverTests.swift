import XCTest
@testable import LookAfterCore

final class HeroObjectiveResolverTests: XCTestCase {

    func testDeepWorkBlockUsesDescriptionNotMechanism() {
        let task = LifeTask(
            title: "Deep Work Block 1",
            description: "Review Azure deployment",
            estimatedMinutes: 45,
            semanticProfile: TaskSemanticProfile(semanticType: .deepWork)
        )
        let context = HeroObjectiveContextBuilder.from(task: task)
        let headline = HeroObjectiveResolver.resolveHeadline(from: context)

        XCTAssertEqual(headline, "Review Azure deployment")
        XCTAssertFalse(headline.lowercased().contains("deep work"))
        XCTAssertFalse(headline.lowercased().contains("focus session"))
        XCTAssertFalse(headline.lowercased().contains("uninterrupted"))
    }

    func testDeepWorkBlockUsesNextStepWhenNoDescription() {
        let task = LifeTask(
            title: "Deep Work Block 2",
            steps: [
                TaskStep(title: "Connect HealthKit entitlement", isCompleted: false),
                TaskStep(title: "Wire sleep sync", isCompleted: false),
            ],
            estimatedMinutes: 30,
            semanticProfile: TaskSemanticProfile(semanticType: .deepWork, subtype: "Apple Health setup")
        )
        let context = HeroObjectiveContextBuilder.from(task: task)
        let headline = HeroObjectiveResolver.resolveHeadline(from: context)

        XCTAssertEqual(headline, "Connect HealthKit entitlement")
        XCTAssertFalse(UserFacingCopy.isInternalExecutionLabel(headline))
    }

    func testHealthKitIntegrationRendersConcreteObjective() {
        let task = LifeTask(title: "HealthKit Integration", estimatedMinutes: 18)
        let headline = HumanLanguage.outcomeHeadline(task: task)

        XCTAssertEqual(headline, "Finish connecting Apple Health")
        XCTAssertFalse(headline.lowercased().contains("uninterrupted"))
    }

    func testSanitizeNeverProducesUninterruptedTimeSession() {
        let sanitized = UserFacingCopy.sanitize("Uninterrupted Time Session")
        XCTAssertTrue(sanitized.isEmpty)
        XCTAssertTrue(UserFacingCopy.isInternalExecutionLabel("Smart Work"))
        XCTAssertTrue(UserFacingCopy.isInternalExecutionLabel("Focus Session"))
        XCTAssertTrue(UserFacingCopy.isInternalExecutionLabel("Productivity Mode"))
    }

    func testCommunicationTaskInfersReplyObjective() {
        let task = LifeTask(
            title: "Muhammad Isra",
            description: "",
            lifeArea: .relationships,
            estimatedMinutes: 5
        )
        let context = HeroObjectiveContextBuilder.from(task: task)
        let raw = HeroObjectiveResolver.resolveRawObjective(from: context)

        XCTAssertEqual(raw, "Reply to Muhammad Isra")
    }

    func testGuitarPracticeFromDescription() {
        let task = LifeTask(
            title: "Focus Block 1",
            description: "Practice fingerstyle guitar",
            estimatedMinutes: 45,
            semanticProfile: TaskSemanticProfile(semanticType: .deepWork)
        )
        let headline = HumanLanguage.outcomeHeadline(task: task)

        XCTAssertEqual(headline, "Practice fingerstyle guitar")
    }

    func testInternalTitleAloneDoesNotSurface() {
        let headline = HumanLanguage.outcomeHeadline(title: "Deep Work Block 3")
        XCTAssertEqual(headline, "Pick up where you left off")
    }

    func testHumanizeBriefingLineRecoveryModeDoesNotLoop() {
        let input = "You are in recovery mode today so take it easy and protect your sleep."
        let output = UserFacingCopy.humanizeBriefingLine(input)
        XCTAssertTrue(output.contains("in recovery mode"))
        XCTAssertFalse(output.contains("in in in"))
        XCTAssertLessThan(output.count, input.count + 40)
    }
}
