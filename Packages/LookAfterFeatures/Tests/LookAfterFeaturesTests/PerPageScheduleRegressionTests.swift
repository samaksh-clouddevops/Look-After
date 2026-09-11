import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

final class PerPageScheduleRegressionTests: XCTestCase {
    @MainActor private var store: InMemoryTaskStore!
    @MainActor private var viewModel: TasksViewModel!
    private var calendar: Calendar { TestCalendarFixtures.calendar }
    private var today: Date { TestCalendarFixtures.today }

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        await configureFixture()
    }

    @MainActor
    private func configureFixture() {
        store = InMemoryTaskStore(referenceDate: today, calendar: calendar)
        let glm = mockGLMService()
        viewModel = TasksViewModel(
            taskRepo: store,
            decomposer: TaskDecomposer(glmService: glm),
            autoFiller: TaskAutoFiller(glmService: glm),
            taskImporter: TaskImporter(glmService: glm)
        )
    }

    @MainActor
    func testReconcileWithoutDriftDoesNotMutateSchedule() async throws {
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!
        let first = LifeTask(
            title: "Deep work",
            estimatedMinutes: 60,
            scheduledDate: today,
            scheduledTime: nine,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let second = LifeTask(
            title: "Email",
            estimatedMinutes: 30,
            scheduledDate: today,
            scheduledTime: eleven,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        try await store.create(first)
        try await store.create(second)
        await viewModel.loadTasks(userId: "user-1", syncRecurrence: false)

        let before = scheduleSignature(viewModel.tasks)
        await viewModel.reconcileTodaySchedule(userId: "user-1")
        await viewModel.reconcileTodaySchedule(userId: "user-1")
        let after = scheduleSignature(viewModel.tasks)

        XCTAssertEqual(before, after)
    }

    @MainActor
    func testPostPlannerSyncAndReconcileResolvesOverlap() async throws {
        let overlap = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        var left = LifeTask(
            title: "Write",
            estimatedMinutes: 45,
            scheduledDate: today,
            scheduledTime: overlap,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        var right = LifeTask(
            title: "Review",
            estimatedMinutes: 45,
            scheduledDate: today,
            scheduledTime: overlap,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        try await store.create(left)
        try await store.create(right)
        await viewModel.loadTasks(userId: "user-1", syncRecurrence: false)

        // Simulate AI reschedule apply writing overlapping times without reconcile.
        left.scheduledTime = overlap
        right.scheduledTime = overlap
        try await store.update(left)
        try await store.update(right)
        viewModel.refreshFromLocal(userId: "user-1")

        await viewModel.reconcileTodaySchedule(userId: "user-1")

        let active = viewModel.tasks.filter { $0.status.isActive && $0.scheduledTime != nil }
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(active, on: today, calendar: calendar))
    }

    @MainActor
    func testConstraintMigrationOnReconcile() async throws {
        let today = Calendar.current.startOfDay(for: Date())
        let fixed = LifeTask(
            title: "Standup",
            estimatedMinutes: 30,
            scheduledDate: today,
            scheduledTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today),
            tags: ["daily-routine", "fixed"],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        try await store.create(fixed)
        viewModel.refreshFromLocal(userId: "user-1")
        XCTAssertEqual(viewModel.tasks.count, 1)

        await viewModel.migrateConstraintFieldsIfNeeded(userId: "user-1")
        let migrated = try XCTUnwrap(viewModel.tasks.first)
        XCTAssertEqual(migrated.timeConstraintValue, .anchored)
        XCTAssertFalse(migrated.isSchedulerMovable)
    }

    @MainActor
    private func scheduleSignature(_ tasks: [LifeTask]) -> String {
        tasks
            .sorted { $0.id < $1.id }
            .map { task in
                let start = task.scheduledTime?.timeIntervalSince1970 ?? -1
                let end = task.scheduledEndTime?.timeIntervalSince1970 ?? -1
                return "\(task.id):\(start):\(end)"
            }
            .joined(separator: "|")
    }
}

@MainActor
private func mockGLMService() -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "per-page.test.\(UUID().uuidString)"
    ))
    let stub = """
    {"steps":[{"title":"Step 1","estimatedMinutes":5}],"detectedRecurrence":"none"}
    """
    glm.debugCompleteHandler = { _, _ in stub }
    glm.debugSendMessageHandler = { _, _, _, _ in stub }
    return glm
}
