import XCTest
@testable import LookAfterData
import LookAfterCore

@MainActor
final class TaskStoreTests: XCTestCase {
    override func tearDown() {
        TaskRepository.invalidateLocalCache()
        super.tearDown()
    }

    func testRefreshLocalPublishesSnapshot() async throws {
        let repo = TaskRepository()
        let store = TaskStore(taskRepo: repo)
        let userId = "task-store-user-\(UUID().uuidString)"
        let task = LifeTask(title: "One task", userId: userId)
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

    func testWarmLocalCachePopulatesMemoryWithoutBlockingPath() async throws {
        TaskRepository.invalidateLocalCache()
        XCTAssertFalse(TaskRepository.hasWarmedLocalCache)

        let repo = TaskRepository()
        let userId = "task-store-warm-\(UUID().uuidString)"
        let task = LifeTask(title: "Warm task", userId: userId)
        try await repo.create(task)

        TaskRepository.invalidateLocalCache()
        XCTAssertFalse(TaskRepository.hasWarmedLocalCache)

        let store = TaskStore(taskRepo: repo)
        await store.warmLocalCache(for: userId)

        XCTAssertTrue(TaskRepository.hasWarmedLocalCache)
        XCTAssertEqual(store.snapshot.active.count, 1)
        XCTAssertEqual(store.snapshot.active.first?.title, "Warm task")

        // Second warm is a no-op hit on memory.
        await store.warmLocalCache(for: userId)
        XCTAssertEqual(store.snapshot.active.count, 1)
    }
}
