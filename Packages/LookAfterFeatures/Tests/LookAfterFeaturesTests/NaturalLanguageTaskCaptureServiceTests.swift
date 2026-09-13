import XCTest
@testable import LookAfterFeatures
import LookAfterAI
import LookAfterCore

final class NaturalLanguageTaskCaptureServiceTests: XCTestCase {

    // MARK: - Field extraction contract

    func testKnownAndInferredFieldsAreSurfacedWithSource() {
        let json: [String: Any] = [
            "title": "Call the dentist",
            "priority": ["status": "known", "source": "explicit_user_text", "value": "High"],
            "estimatedMinutes": ["status": "inferred", "source": "deterministic_policy", "value": 30]
        ]
        let draft = NaturalLanguageTaskCaptureService.buildDraft(from: json, fallbackTitle: "fallback")

        XCTAssertEqual(draft.title, "Call the dentist")
        XCTAssertEqual(draft.priority.value, .high)
        XCTAssertEqual(draft.priority.status, .known)
        XCTAssertEqual(draft.priority.source, .explicitUserText)
        XCTAssertEqual(draft.estimatedMinutes.value, 30)
        XCTAssertEqual(draft.estimatedMinutes.source, .deterministicPolicy)
    }

    func testAmbiguousFieldHasNilValue() {
        let json: [String: Any] = [
            "title": "Plan the trip",
            "scheduledAt": ["status": "ambiguous", "source": NSNull(), "value": NSNull()]
        ]
        let draft = NaturalLanguageTaskCaptureService.buildDraft(from: json, fallbackTitle: "fallback")

        XCTAssertEqual(draft.scheduledAt.status, .ambiguous)
        XCTAssertNil(draft.scheduledAt.value)
    }

    func testModelInferenceDowngradedToUnknownForPriorityAndMinutes() {
        let json: [String: Any] = [
            "title": "Buy groceries",
            "priority": ["status": "inferred", "source": "model_inference", "value": "Critical"],
            "estimatedMinutes": ["status": "inferred", "source": "model_inference", "value": 45]
        ]
        let draft = NaturalLanguageTaskCaptureService.buildDraft(from: json, fallbackTitle: "fallback")

        XCTAssertEqual(draft.priority.status, .unknown)
        XCTAssertNil(draft.priority.value)
        XCTAssertEqual(draft.estimatedMinutes.status, .unknown)
        XCTAssertNil(draft.estimatedMinutes.value)
    }

    func testModelInferenceAllowedForLifeArea() {
        let json: [String: Any] = [
            "title": "Water the plants",
            "lifeArea": ["status": "inferred", "source": "model_inference", "value": "Home Management"]
        ]
        let draft = NaturalLanguageTaskCaptureService.buildDraft(from: json, fallbackTitle: "fallback")

        XCTAssertEqual(draft.lifeArea.value, .home)
        XCTAssertEqual(draft.lifeArea.source, .modelInference)
    }

    func testMalformedEnumStringDowngradesToUnknown() {
        let json: [String: Any] = [
            "title": "Something",
            "difficulty": ["status": "known", "source": "explicit_user_text", "value": "SuperHard"]
        ]
        let draft = NaturalLanguageTaskCaptureService.buildDraft(from: json, fallbackTitle: "fallback")

        XCTAssertEqual(draft.difficulty.status, .unknown)
        XCTAssertNil(draft.difficulty.value)
    }

    func testMissingTitleFallsBackToRawInput() {
        let json: [String: Any] = [:]
        let draft = NaturalLanguageTaskCaptureService.buildDraft(from: json, fallbackTitle: "raw user text")
        XCTAssertEqual(draft.title, "raw user text")
    }

    // MARK: - Cross-field validation

    func testScheduledAtAfterDeadlineIsFlagged() {
        let now = Date()
        var draft = NaturalLanguageTaskDraft(title: "Submit report")
        draft.deadline = ExtractedField(value: now.addingTimeInterval(3_600), status: .known, source: .explicitUserText)
        draft.scheduledAt = ExtractedField(value: now.addingTimeInterval(7_200), status: .known, source: .explicitUserText)

        let validated = NaturalLanguageTaskDraftValidator.validated(draft, now: now)
        XCTAssertTrue(validated.flaggedInconsistencies.contains("scheduledAt-after-deadline"))
    }

    func testScheduledAtInPastIsFlagged() {
        let now = Date()
        var draft = NaturalLanguageTaskDraft(title: "Renew passport")
        draft.scheduledAt = ExtractedField(value: now.addingTimeInterval(-3_600), status: .known, source: .explicitUserText)

        let validated = NaturalLanguageTaskDraftValidator.validated(draft, now: now)
        XCTAssertTrue(validated.flaggedInconsistencies.contains("scheduledAt-in-past"))
    }

    func testNegativeMinutesAreClampedNotFabricated() {
        var draft = NaturalLanguageTaskDraft(title: "Quick task")
        draft.estimatedMinutes = ExtractedField(value: -10, status: .known, source: .explicitUserText)

        let validated = NaturalLanguageTaskDraftValidator.validated(draft)
        XCTAssertEqual(validated.estimatedMinutes.value, TaskDurationPolicy.minimumMinutes)
    }

    func testUnknownMinutesAreNotFabricatedByValidator() {
        let draft = NaturalLanguageTaskDraft(title: "Ambient task")
        let validated = NaturalLanguageTaskDraftValidator.validated(draft)
        XCTAssertNil(validated.estimatedMinutes.value)
        XCTAssertEqual(validated.estimatedMinutes.status, .unknown)
    }

    // MARK: - Service-level errors (no network — deterministic test doubles only)

    func testEmptyInputThrowsEmptyInputError() async {
        let glm = mockNLGLMService(response: "{}")
        do {
            _ = try await NaturalLanguageTaskCaptureService.extractDraft(from: "   ", glm: glm)
            XCTFail("Expected emptyInput error")
        } catch let error as NaturalLanguageTaskCaptureError {
            XCTAssertEqual(error, .emptyInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedResponseThrowsParseError() async {
        let glm = mockNLGLMService(response: "not json at all")
        do {
            _ = try await NaturalLanguageTaskCaptureService.extractDraft(from: "Call mom", glm: glm)
            XCTFail("Expected parseError")
        } catch let error as NaturalLanguageTaskCaptureError {
            XCTAssertEqual(error, .parseError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidResponseProducesReviewReadyDraft() async throws {
        let glm = mockNLGLMService(response: """
        {"title":"Call the dentist","priority":{"status":"known","source":"explicit_user_text","value":"High"}}
        """)
        let draft = try await NaturalLanguageTaskCaptureService.extractDraft(from: "Call the dentist, high priority", glm: glm)
        XCTAssertEqual(draft.title, "Call the dentist")
        XCTAssertEqual(draft.priority.value, .high)
    }
}

extension NaturalLanguageTaskCaptureError: Equatable {
    public static func == (lhs: NaturalLanguageTaskCaptureError, rhs: NaturalLanguageTaskCaptureError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyInput, .emptyInput), (.parseError, .parseError): return true
        default: return false
        }
    }
}

private func mockNLGLMService(response: String) -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "nl-capture.test.\(UUID().uuidString)"
    ))
    glm.debugCompleteHandler = { _, _ in response }
    glm.debugSendMessageHandler = { _, _, _, _ in response }
    return glm
}
