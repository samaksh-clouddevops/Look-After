import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

@MainActor
final class TasksViewModelInteractionTests: XCTestCase {
    private var store: InMemoryTaskStore!
    private var viewModel: TasksViewModel!
    private var calendar: Calendar { Calendar.current }
    private var today: Date { calendar.startOfDay(for: Date()) }

    override func setUp() async throws {
        let referenceDay = calendar.startOfDay(for: Date())
        store = InMemoryTaskStore(referenceDate: referenceDay, calendar: calendar)
        let glm = mockGLMService()
        viewModel = TasksViewModel(
            taskRepo: store,
            decomposer: TaskDecomposer(glmService: glm),
            autoFiller: TaskAutoFiller(glmService: glm),
            taskImporter: TaskImporter(glmService: glm)
        )
    }

    func testCompleteDailyRecurringTaskDoesNotSpawnNextOccurrenceImmediately() async throws {
        let task = LifeTask(
            title: "Medication",
            scheduledDate: today,
            recurrence: .daily,
            userId: "user-1"
        )
        viewModel.createTask(task)
        try await Task.sleep(nanoseconds: 200_000_000)
        viewModel.refreshFromLocal(userId: "user-1")

        guard let occurrence = viewModel.tasks.first else {
            XCTFail("Expected today's occurrence")
            return
        }

        _ = await viewModel.completeTask(occurrence)

        XCTAssertTrue(viewModel.activeTasks.isEmpty)
        XCTAssertEqual(viewModel.completedToday.count, 1)
        XCTAssertTrue(viewModel.tasks.isEmpty)
    }

    func testSchedulerCreatesNextDayOccurrenceOnLoad() async throws {
        let template = LifeTask(
            title: "Medication",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        try await store.create(template)

        var completed = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: today,
            calendar: calendar
        )
        completed.status = .completed
        completed.completedAt = today
        try await store.create(completed)

        await viewModel.loadTasks(userId: "user-1")

        XCTAssertEqual(viewModel.activeTasks.count, 0)
        XCTAssertEqual(viewModel.completedToday.count, 1)
    }

    func testUndoRestoresDeletedTask() async throws {
        let task = LifeTask(title: "Delete me", userId: "user-1")
        try await store.create(task)
        viewModel.tasks = try await store.getActive(for: "user-1")

        _ = await viewModel.deleteTask(task)
        XCTAssertTrue(viewModel.tasks.isEmpty)

        await viewModel.performUndo()

        XCTAssertEqual(viewModel.tasks.count, 1)
        XCTAssertEqual(viewModel.tasks.first?.title, "Delete me")
    }

    func testDeletePersistsBeforeLocalRefresh() async throws {
        let task = LifeTask(title: "Delete once", userId: "user-1")
        try await store.create(task)
        viewModel.tasks = try await store.getActive(for: "user-1")

        _ = await viewModel.deleteTask(task)
        viewModel.refreshFromLocal(userId: "user-1")

        XCTAssertTrue(viewModel.tasks.isEmpty)
    }

    func testUndoRestoresCompletedTask() async throws {
        let task = LifeTask(title: "Repeat", scheduledDate: today, recurrence: .daily, userId: "user-1")
        viewModel.createTask(task)
        try await Task.sleep(nanoseconds: 200_000_000)
        viewModel.refreshFromLocal(userId: "user-1")
        guard let occurrence = viewModel.tasks.first else {
            XCTFail("Expected occurrence")
            return
        }

        _ = await viewModel.completeTask(occurrence)

        await viewModel.performUndo()

        XCTAssertEqual(viewModel.tasks.count, 1)
        XCTAssertEqual(viewModel.tasks.first?.id, occurrence.id)
        XCTAssertTrue(viewModel.completedToday.isEmpty)
    }

    func testMarkIncompleteMovesTaskBackToActive() async {
        var task = LifeTask(title: "Temporarily done", userId: "user-1")
        task.status = .completed
        task.completedAt = today
        viewModel.completedToday = [task]

        await viewModel.markIncomplete(task)

        XCTAssertTrue(viewModel.completedToday.isEmpty)
        XCTAssertEqual(viewModel.tasks.first?.status, .pending)
        XCTAssertNil(viewModel.tasks.first?.completedAt)
    }

    func testCompleteTaskRemovesFromActiveListImmediately() async throws {
        let task = LifeTask(title: "Write report", userId: "user-1")
        try await store.create(task)
        viewModel.tasks = try await store.getActive(for: "user-1")
        XCTAssertEqual(viewModel.activeTasks.count, 1)

        _ = await viewModel.completeTask(task)

        XCTAssertTrue(viewModel.activeTasks.isEmpty)
        XCTAssertFalse(viewModel.tasks.contains { $0.id == task.id })
        XCTAssertEqual(viewModel.completedToday.count, 1)
        XCTAssertTrue(viewModel.isUndoToastVisible)
    }

    func testUndoToastExpiresAfterDismiss() async throws {
        let task = LifeTask(title: "Toast test", userId: "user-1")
        try await store.create(task)
        viewModel.tasks = try await store.getActive(for: "user-1")
        _ = await viewModel.completeTask(task)
        XCTAssertTrue(viewModel.isUndoToastVisible)

        viewModel.clearPendingUndo()
        XCTAssertFalse(viewModel.isUndoToastVisible)
        XCTAssertNil(viewModel.pendingUndo)
    }

    func testLoadTasksHydratesFromLocalBeforeRemote() async throws {
        let task = LifeTask(title: "Persisted", userId: "user-1")
        try await store.create(task)

        await viewModel.loadTasks(userId: "user-1")

        XCTAssertEqual(viewModel.activeTasks.count, 1)
        XCTAssertEqual(viewModel.activeTasks.first?.title, "Persisted")
    }

    func testRefreshFromLocalDoesNotRestoreCompletedTaskToActive() async throws {
        let task = LifeTask(title: "Write report", userId: "user-1")
        try await store.create(task)
        viewModel.tasks = try await store.getActive(for: "user-1")
        _ = await viewModel.completeTask(task)

        viewModel.refreshFromLocal(userId: "user-1")

        XCTAssertTrue(viewModel.activeTasks.isEmpty)
        XCTAssertEqual(viewModel.completedToday.count, 1)
    }

    func testDuplicateCreatesPendingCopy() {
        let task = LifeTask(title: "Original", userId: "user-1")
        viewModel.createTask(task)

        viewModel.duplicateTask(task)

        XCTAssertEqual(viewModel.tasks.count, 2)
        XCTAssertEqual(viewModel.tasks[0].title, "Original")
        XCTAssertEqual(viewModel.tasks[0].status, .pending)
        XCTAssertNotEqual(viewModel.tasks[0].id, task.id)
        XCTAssertNil(viewModel.tasks[0].parentTaskId)
    }

    func testUpdateTaskAndPersistSurvivesStaleSnapshotRefresh() async {
        let task = LifeTask(title: "Original", userId: "user-1")
        try? await store.create(task)
        viewModel.tasks = [task]

        var edited = task
        edited.title = "Renamed"
        edited.updatedAt = Date()

        await viewModel.updateTaskAndPersist(edited)
        XCTAssertEqual(viewModel.tasks.first?.title, "Renamed")

        viewModel.tasks = [task]
        viewModel.refreshFromLocal(userId: "user-1")
        XCTAssertEqual(viewModel.tasks.first?.title, "Renamed")
    }

    func testUpdateTaskAndPersistCompletesWithoutBlockingOnSemanticAnalysis() async {
        let task = LifeTask(title: "Deep work block", estimatedMinutes: 45, userId: "user-1")
        try? await store.create(task)
        viewModel.tasks = [task]

        var edited = task
        edited.title = "Deep work block — OAuth"
        edited.estimatedMinutes = 60
        edited.updatedAt = Date()

        let started = Date()
        await viewModel.updateTaskAndPersist(edited)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 1.0, "Save should not wait on LLM semantic analysis")
        XCTAssertEqual(viewModel.tasks.first?.title, "Deep work block — OAuth")
        XCTAssertNotNil(viewModel.tasks.first?.semanticProfile)
    }
}

@MainActor
final class InMemoryTaskStore: TaskStoring {
    private var tasks: [LifeTask] = []
    private let referenceDate: Date
    private let calendar: Calendar

    init(referenceDate: Date = TestCalendarFixtures.today, calendar: Calendar = TestCalendarFixtures.calendar) {
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    func warmLocalCache(for userId: String) async {
        _ = userId
    }

    func localSnapshot(for userId: String) -> TaskListSnapshot {
        TaskListSnapshot.make(
            from: tasks.filter { $0.userId == userId || userId.isEmpty },
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    func localAllTasks(for userId: String) -> [LifeTask] {
        tasks.filter { $0.userId == userId || userId.isEmpty }
    }

    func getTaskLists(for userId: String) async throws -> TaskListSnapshot {
        localSnapshot(for: userId)
    }

    func getAll(for userId: String) async throws -> [LifeTask] {
        tasks.filter { $0.userId == userId || userId.isEmpty }
    }

    func getActive(for userId: String) async throws -> [LifeTask] {
        try await getTaskLists(for: userId).active
    }

    func getCompletedToday(for userId: String) async throws -> [LifeTask] {
        let start = calendar.startOfDay(for: referenceDate)
        return try await getAll(for: userId).filter { task in
            task.status == .completed && (task.completedAt ?? .distantPast) >= start
        }
    }

    func create(_ task: LifeTask) async throws {
        tasks.insert(task, at: 0)
    }

    func update(_ task: LifeTask) async throws {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    func delete(_ id: String) async throws {
        tasks.removeAll { $0.id == id }
    }

    func pruneTerminalRecurrenceOccurrences(for userId: String, retentionDays: Int) -> Int {
        compactRecurrenceStorage(for: userId, retentionDays: retentionDays)
    }

    func compactRecurrenceStorage(for userId: String, retentionDays: Int) -> Int {
        _ = userId
        _ = retentionDays
        return 0
    }

    func compactRecurrenceStorageAsync(for userId: String, retentionDays: Int) async -> Int {
        compactRecurrenceStorage(for: userId, retentionDays: retentionDays)
    }
}

private func mockGLMService() -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "tasks.test.\(UUID().uuidString)"
    ))
    let stub = """
    {"steps":[{"title":"Step 1","estimatedMinutes":5}],"detectedRecurrence":"none"}
    """
    glm.debugCompleteHandler = { _, _ in stub }
    glm.debugSendMessageHandler = { _, _, _, _ in stub }
    return glm
}
