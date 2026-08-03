import XCTest
@testable import LookAfterAI
import LookAfterCore

final class CognitiveAITests: XCTestCase {

    func testTaskDecomposerParsing() async throws {
        let glm = MockGLM.service(stubbedResponse: """
        {
            "detectedRecurrence": "weekly",
            "steps": [
                { "title": "Open IDE and create project", "estimatedMinutes": 5 },
                { "title": "Setup basic layout grid", "estimatedMinutes": 10 }
            ]
        }
        """)

        let decomposer = TaskDecomposer(glmService: glm)
        let task = LifeTask(title: "Build iOS Dashboard")

        let result = try await decomposer.decompose(task: task)

        XCTAssertEqual(result.steps.count, 2)
        XCTAssertEqual(result.steps[0].title, "Open IDE and create project")
        XCTAssertEqual(result.steps[0].estimatedMinutes, 5)
        XCTAssertEqual(result.recurrence, .weekly)
    }

    func testTaskDecomposerFallbackOnInvalidJSON() async throws {
        let glm = MockGLM.service(stubbedResponse: "Not valid JSON response")

        let decomposer = TaskDecomposer(glmService: glm)
        let task = LifeTask(title: "Clean Desk")

        let result = try await decomposer.decompose(task: task)

        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps[0].title, "Start working on: Clean Desk")
    }
}
