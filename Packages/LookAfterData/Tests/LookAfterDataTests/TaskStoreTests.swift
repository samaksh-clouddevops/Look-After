import XCTest
@testable import LookAfterData
import LookAfterCore

@MainActor
final class TaskStoreTests: XCTestCase {
    func testRefreshLocalPublishesSnapshot() async throws {
        let repo = TaskRepository()
        let store = TaskStore(taskRepo: repo)
        let userId = "task-store-user-\(UUID().uuidString)"
        var task = LifeTask(title: "One task", userId: userId)
        try await repo.create(task)

        store.refreshLocal(userId: userId)

        XCTAssertEqual(store.snapshot.active.count, 1)
        XCTAssertEqual(store.snapshot.active.first?.title, "One task")
        XCTAssertEqual(store.allTasks.count, 1)
    }

    func testCreateUpdatesPublishedSnapshot() async throws {
        let store = TaskStore(taskRepo: TaskRepository())
        let userId = "task-store-create-\(UUID().uuidString)"
        store.refreshLocal(userId: userId)

        let task = LifeTask(title: "Created via store", userId: userId)
        try await store.create(task)

        XCTAssertEqual(store.snapshot.active.count, 1)
        XCTAssertEqual(store.snapshot.active.first?.title, "Created via store")
    }
}
