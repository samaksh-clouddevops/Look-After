import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class BrainVoiceWelcomeBuilderTests: XCTestCase {

    func testWelcomeUsesHeroTaskWhenAvailable() {
        var presentation = BrainPresentation.empty
        presentation.greeting = "Good evening"
        presentation.hero = BrainHeroPresentation(
            task: nil,
            title: "Gym",
            supportingLine: "",
            scheduledLabel: nil,
            durationMinutes: 60,
            whyReasons: [],
            buttonLabel: "Start",
            isPastDue: false,
            kind: .exercise
        )

        let message = BrainVoiceWelcomeBuilder.message(
            presentation: presentation,
            userName: "Sam"
        )

        XCTAssertTrue(message.contains("Good evening, Sam"))
        XCTAssertTrue(message.contains("Gym"))
    }

    func testWelcomeUsesContinuationWhenConversationExists() {
        let message = BrainVoiceWelcomeBuilder.message(
            presentation: .empty,
            userName: "Sam",
            hasPriorConversation: true
        )

        XCTAssertTrue(message.contains("still here"))
    }
}
