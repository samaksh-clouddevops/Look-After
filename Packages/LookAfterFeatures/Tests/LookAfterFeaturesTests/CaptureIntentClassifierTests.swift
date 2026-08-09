import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class CaptureIntentClassifierTests: XCTestCase {
    func testHeuristicTaskFromPrefix() {
        let request = CaptureRequest(text: "[Task] Buy milk")
        let decision = CaptureIntentClassifier.heuristicDecision(for: request, forcedIntent: nil)
        XCTAssertEqual(decision.intent, .task)
        XCTAssertEqual(decision.title, "Buy milk")
    }

    func testHeuristicMoodFromHealthPrefix() {
        let request = CaptureRequest(text: "[Health] Mood: Low — tired")
        let decision = CaptureIntentClassifier.heuristicDecision(for: request, forcedIntent: nil)
        XCTAssertEqual(decision.intent, .mood)
    }

    func testForcedChipHint() {
        let request = CaptureRequest(text: "Remember dentist", hintedIntent: .event)
        let decision = CaptureIntentClassifier.heuristicDecision(for: request, forcedIntent: .event)
        XCTAssertEqual(decision.intent, .event)
        XCTAssertGreaterThan(decision.confidence, 0.8)
    }

    func testOutcomeToastMessages() {
        let task = CaptureOutcome.taskCreated(taskId: "1", title: "Buy milk")
        XCTAssertTrue(task.plainToastMessage.contains("Buy milk"))
        let waiting = CaptureOutcome.needsReview(inboxId: "x", preview: "ambiguous")
        XCTAssertTrue(waiting.plainToastMessage.contains("Inbox"))
    }
}
