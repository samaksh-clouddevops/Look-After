import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

final class PlanMutationApplierRescheduleTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    private var today: Date { TestCalendarFixtures.today }

    @MainActor
    func testRescheduleTaskByTitleUpdatesScheduledTime() async throws {
        let today = calendar.startOfDay(for: Date())
        let store = RescheduleTestTaskStore(referenceDate: today, calendar: calendar)
        let glm = mockGLMService()
        let tasksVM = TasksViewModel(
            taskRepo: store,
            decomposer: TaskDecomposer(glmService: glm),
            autoFiller: TaskAutoFiller(glmService: glm),
            taskImporter: TaskImporter(glmService: glm)
        )
        let modulesVM = LifeModulesViewModel()

        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        var task = LifeTask(
            title: "Email inbox",
            estimatedMinutes: 30,
            scheduledDate: today,
            scheduledTime: start,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        try await store.create(task)
        await tasksVM.loadTasks(userId: "user-1")
        guard let stored = tasksVM.tasks.first else {
            XCTFail("Expected stored task")
            return
        }

        let mutation = PlanMutation(
            kind: .rescheduleTask,
            title: "Email inbox",
            startHour: 14,
            startMinute: 30
        )
        var medications: [Medication] = []
        let applier = PlanMutationApplier()
        let result = await applier.apply(
            mutations: [mutation],
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: "user-1",
            medications: &medications
        )

        XCTAssertEqual(result.appliedCount, 1, result.skippedReasons.joined(separator: "; "))
        XCTAssertTrue(result.skippedReasons.isEmpty)
        let updated = try await store.getAll(for: "user-1").first { $0.id == stored.id }
        XCTAssertNotNil(updated?.scheduledTime)
        XCTAssertNotEqual(updated?.scheduledTime, start)
    }

    @MainActor
    func testRescheduleSkipsUserPlacedUnlessOverrideAllowed() async throws {
        let today = calendar.startOfDay(for: Date())
        let store = RescheduleTestTaskStore(referenceDate: today, calendar: calendar)
        let glm = mockGLMService()
        let tasksVM = TasksViewModel(
            taskRepo: store,
            decomposer: TaskDecomposer(glmService: glm),
            autoFiller: TaskAutoFiller(glmService: glm),
            taskImporter: TaskImporter(glmService: glm)
        )
        let modulesVM = LifeModulesViewModel()

        let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        var task = LifeTask(
            title: "Deep work",
            estimatedMinutes: 45,
            scheduledDate: today,
            scheduledTime: start,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        task.userPlacedScheduleAt = Date()
        try await store.create(task)
        await tasksVM.loadTasks(userId: "user-1")

        let mutation = PlanMutation(
            kind: .rescheduleTask,
            title: "Deep work",
            startHour: 15,
            startMinute: 0
        )
        var medications: [Medication] = []
        let applier = PlanMutationApplier()
        ScheduleMutationIdempotencyStore.shared.reset()

        let blocked = await applier.apply(
            mutations: [mutation],
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: "user-1",
            medications: &medications,
            allowUserPlacedOverride: false
        )
        XCTAssertEqual(blocked.appliedCount, 0)
        XCTAssertFalse(blocked.skippedReasons.isEmpty)

        ScheduleMutationIdempotencyStore.shared.reset()
        let allowed = await applier.apply(
            mutations: [mutation],
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: "user-1",
            medications: &medications,
            allowUserPlacedOverride: true
        )
        XCTAssertEqual(allowed.appliedCount, 1, allowed.skippedReasons.joined(separator: "; "))
        let updated = try await store.getAll(for: "user-1").first { $0.title == "Deep work" }
        XCTAssertNotEqual(updated?.scheduledTime, start)
        XCTAssertNil(updated?.userPlacedScheduleAt)
    }

    @MainActor
    func testRescheduleParserAliasesMapToRescheduleTask() {
        XCTAssertEqual(PlanMutationKind.fromLLM("movetask"), .rescheduleTask)
        XCTAssertEqual(PlanMutationKind.fromLLM("scheduletask"), .rescheduleTask)
    }
}

@MainActor
private func mockGLMService() -> GLMService {
    let glm = GLMService.makeForTesting(keyManager: GLMKeyManager(
        secretStore: InMemorySecretStore(),
        metadataKey: "reschedule.test.\(UUID().uuidString)"
    ))
    let stub = """
    {"steps":[{"title":"Step 1","estimatedMinutes":5}],"detectedRecurrence":"none"}
    """
    glm.debugCompleteHandler = { _, _ in stub }
    glm.debugSendMessageHandler = { _, _, _, _ in stub }
    return glm
}

private final class RescheduleTestTaskStore: TaskStoring {
    private var tasks: [LifeTask] = []
    private let referenceDate: Date
    private let calendar: Calendar

    init(referenceDate: Date = TestCalendarFixtures.today, calendar: Calendar = TestCalendarFixtures.calendar) {
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    @MainActor
    func warmLocalCache(for userId: String) async { _ = userId }

    @MainActor
    func localSnapshot(for userId: String) -> TaskListSnapshot {
        TaskListSnapshot.make(
            from: tasks.filter { $0.userId == userId || userId.isEmpty },
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    @MainActor
    func localAllTasks(for userId: String) -> [LifeTask] {
        tasks.filter { $0.userId == userId || userId.isEmpty }
    }

    @MainActor
    func getTaskLists(for userId: String) async throws -> TaskListSnapshot {
        localSnapshot(for: userId)
    }

    @MainActor
    func getAll(for userId: String) async throws -> [LifeTask] {
        tasks.filter { $0.userId == userId || userId.isEmpty }
    }

    @MainActor
    func getActive(for userId: String) async throws -> [LifeTask] {
        try await getTaskLists(for: userId).active
    }

    @MainActor
    func getCompletedToday(for userId: String) async throws -> [LifeTask] {
        let start = calendar.startOfDay(for: referenceDate)
        return try await getAll(for: userId).filter { task in
            task.status == .completed && (task.completedAt ?? .distantPast) >= start
        }
    }

    @MainActor
    func create(_ task: LifeTask) async throws {
        tasks.insert(task, at: 0)
    }

    @MainActor
    func update(_ task: LifeTask) async throws {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    @MainActor
    func delete(_ id: String) async throws {
        tasks.removeAll { $0.id == id }
    }

    @MainActor
    func pruneTerminalRecurrenceOccurrences(for userId: String, retentionDays: Int) -> Int {
        compactRecurrenceStorage(for: userId, retentionDays: retentionDays)
    }

    @MainActor
    func compactRecurrenceStorage(for userId: String, retentionDays: Int) -> Int {
        _ = userId
        _ = retentionDays
        return 0
    }

    @MainActor
    func compactRecurrenceStorageAsync(for userId: String, retentionDays: Int) async -> Int {
        compactRecurrenceStorage(for: userId, retentionDays: retentionDays)
    }
}
