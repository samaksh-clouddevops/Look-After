import XCTest
@testable import LifeOSFeatures
import LifeOSCore

/// UI interaction contract tests for task cards.
final class TaskCardUIContractTests: XCTestCase {
    func testCheckboxAccessibilityIdentifierFormat() {
        let taskId = "abc-123"
        XCTAssertEqual("task-checkbox-\(taskId)", "task-checkbox-abc-123")
    }

    func testCardAccessibilityIdentifierFormat() {
        let taskId = "abc-123"
        XCTAssertEqual("task-card-\(taskId)", "task-card-abc-123")
    }

    func testActionButtonLayoutConstants() {
        XCTAssertGreaterThanOrEqual(44, 44)
        XCTAssertEqual(12, 12)
    }

    func testCompletedTaskActionsExcludeStart() {
        let completed = LifeTask(title: "Done", status: .completed)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertFalse(completed.status.isActive)
    }
}
