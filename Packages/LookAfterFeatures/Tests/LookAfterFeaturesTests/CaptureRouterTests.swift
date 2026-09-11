import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class CaptureRouterTests: XCTestCase {

    @MainActor
    override func tearDown() async throws {
        await CaptureOfflineQueue.shared.clear()
        try await super.tearDown()
    }

    @MainActor
    func testOfflineQueueEnqueueAndDrain() async {
        let request = CaptureRequest(
            text: "Buy milk offline",
            source: .bottomNav,
            contextHints: CaptureContextHints(screen: "test")
        )
        CaptureOfflineQueue.shared.enqueue(request, userId: "user-1")
        XCTAssertEqual(CaptureOfflineQueue.shared.pendingRecords().count, 1)

        var routed = false
        let results = await CaptureOfflineQueue.shared.processPending(userId: "user-1") { req, uid in
            routed = true
            XCTAssertEqual(req.text, "Buy milk offline")
            XCTAssertEqual(uid, "user-1")
            return CaptureRouteResult(outcome: .taskCreated(taskId: "t1", title: "Buy milk offline"))
        }
        XCTAssertTrue(routed)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(CaptureOfflineQueue.shared.pendingRecords().isEmpty)
    }

    @MainActor
    func testHeuristicRoutesEventWithTimeHint() {
        let request = CaptureRequest(
            text: "Dentist Tuesday at 3pm",
            hintedIntent: .event,
            contextHints: CaptureContextHints(screen: "todayTimeline")
        )
        let decision = CaptureIntentClassifier.heuristicDecision(for: request, forcedIntent: .event)
        XCTAssertEqual(decision.intent, .event)
        XCTAssertGreaterThan(decision.confidence, 0.8)
    }

    @MainActor
    func testAmbiguousTextFallsToTaskHeuristic() {
        let request = CaptureRequest(text: "maybe something later")
        let decision = CaptureIntentClassifier.heuristicDecision(for: request, forcedIntent: nil)
        XCTAssertEqual(decision.intent, .task)
    }

    @MainActor
    func testMoodChipRoutesMoodIntent() {
        let request = CaptureRequest(text: "Feeling tired", hintedIntent: .mood)
        let decision = CaptureIntentClassifier.heuristicDecision(for: request, forcedIntent: .mood)
        XCTAssertEqual(decision.intent, .mood)
    }

    @MainActor
    func testQueuedOfflineOutcomeMessage() {
        let outcome = CaptureOutcome.queuedOffline(preview: "Remember dentist")
        XCTAssertTrue(outcome.plainToastMessage.contains("offline"))
        XCTAssertTrue(outcome.plainToastMessage.contains("Remember dentist"))
    }
}
