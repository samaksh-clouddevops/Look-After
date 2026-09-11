import XCTest
@testable import LookAfterData
import LookAfterCore

final class TaskSyncOutboxTests: XCTestCase {
    @MainActor
    func testEnqueueIncreasesPendingCount() async {
        TaskSyncOutbox.shared.resetForTests()
        XCTAssertEqual(TaskSyncOutbox.shared.pendingCount, 0)

        var task = LifeTask(title: "Outbox test")
        task.userId = "user_outbox_test"
        TaskSyncOutbox.shared.enqueueUpsert(task, merge: false)

        XCTAssertGreaterThanOrEqual(TaskSyncOutbox.shared.pendingCount, 1)

        // Without cloud sync available, drain should leave entries pending.
        let completed = await TaskSyncOutbox.shared.drain()
        XCTAssertEqual(completed, 0)
        XCTAssertGreaterThanOrEqual(TaskSyncOutbox.shared.pendingCount, 1)

        TaskSyncOutbox.shared.resetForTests()
    }

    @MainActor
    func testDeleteReplacesPriorUpsertForSameTask() {
        TaskSyncOutbox.shared.resetForTests()
        var task = LifeTask(title: "Replace me")
        task.id = "task_outbox_1"
        task.userId = "u1"
        TaskSyncOutbox.shared.enqueueUpsert(task, merge: true)
        TaskSyncOutbox.shared.enqueueDelete(taskId: task.id, userId: "u1")
        XCTAssertEqual(TaskSyncOutbox.shared.pendingCount, 1)
        TaskSyncOutbox.shared.resetForTests()
    }
}
