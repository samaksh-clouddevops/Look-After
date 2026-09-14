import XCTest
@testable import LookAfterData
import LookAfterCore

@MainActor
final class TaskStoreTests: XCTestCase {
    private var taskStore: TaskSQLiteStore!

    override func setUp() {
        super.setUp()
        taskStore = TaskSQLiteStore(inMemory: true)
    }

    override func tearDown() {
        TaskRepository.invalidateLocalCache()
        try? taskStore.reset()
        super.tearDown()
    }

    private func makeStore() -> TaskStore {
        TaskStore(taskRepo: TaskRepository(taskStore: taskStore))
    }

    func testRefreshLocalPublishesSnapshot() async throws {
        let repo = TaskRepository(taskStore: taskStore)
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
        let store = makeStore()
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

        let repo = TaskRepository(taskStore: taskStore)
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

    func testGetAllWarmsDiskBeforeTreatingLocalAsEmpty() async throws {
        TaskRepository.invalidateLocalCache()
        let userId = "task-getall-warm-\(UUID().uuidString)"
        let task = LifeTask(title: "Must survive getAll", userId: userId)
        try taskStore.replaceAllSync([task])

        let repo = TaskRepository(taskStore: taskStore)
        XCTAssertFalse(TaskRepository.hasWarmedLocalCache)

        let loaded = try await repo.getAll(for: userId)

        XCTAssertTrue(TaskRepository.hasWarmedLocalCache)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Must survive getAll")
    }

    func testCreateAfterColdCacheDoesNotReplaceExistingRows() async throws {
        TaskRepository.invalidateLocalCache()
        let userId = "task-create-warm-\(UUID().uuidString)"
        let existing = LifeTask(title: "Already on disk", userId: userId)
        try taskStore.replaceAllSync([existing])

        let repo = TaskRepository(taskStore: taskStore)
        XCTAssertFalse(TaskRepository.hasWarmedLocalCache)

        let created = LifeTask(title: "Captured during cold start", userId: userId)
        try await repo.create(created)

        let all = repo.localAllTasks(for: userId)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(where: { $0.title == "Already on disk" }))
        XCTAssertTrue(all.contains(where: { $0.title == "Captured during cold start" }))
    }

    func testCompactionKeepsTasksAddedWhileSnapshotIsStale() async throws {
        TaskRepository.invalidateLocalCache()
        let repo = TaskRepository(taskStore: taskStore)
        let userId = "task-compact-\(UUID().uuidString)"
        let template = LifeTask(
            id: "tmpl-\(UUID().uuidString)",
            title: "Brush teeth",
            recurrence: .daily,
            userId: userId,
            isRecurrenceTemplate: true
        )
        let superseded = LifeTask(
            id: "occ-old-\(UUID().uuidString)",
            title: "Brush teeth",
            status: .superseded,
            scheduledDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()),
            parentTaskId: template.id,
            userId: userId
        )
        try await repo.create(template)
        try await repo.create(superseded)

        let unrelated = LifeTask(title: "Do not drop me", userId: userId)
        try await repo.create(unrelated)

        let removed = await repo.compactRecurrenceStorageAsync(for: userId, retentionDays: 7)
        XCTAssertEqual(removed, 1)

        let remaining = repo.localAllTasks(for: userId)
        XCTAssertTrue(remaining.contains(where: { $0.title == "Do not drop me" }))
        XCTAssertTrue(remaining.contains(where: { $0.id == template.id }))
        XCTAssertFalse(remaining.contains(where: { $0.id == superseded.id }))
    }
}
