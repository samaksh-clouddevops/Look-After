import XCTest
@testable import LookAfterFeatures
@testable import LookAfterAI
import LookAfterCore
import LookAfterData

@MainActor
final class PlanMutationApplierRescheduleTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    private var today: Date { TestCalendarFixtures.today }

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

    func testRescheduleParserAliasesMapToRescheduleTask() {
        XCTAssertEqual(PlanMutationKind.fromLLM("movetask"), .rescheduleTask)
        XCTAssertEqual(PlanMutationKind.fromLLM("scheduletask"), .rescheduleTask)
    }
}

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

    func warmLocalCache(for userId: String) async { _ = userId }

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
