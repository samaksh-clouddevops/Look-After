import Foundation
import Testing
import LookAfterCore
@testable import LookAfterAI
@testable import LookAfterFeatures

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct TaskMutationRegressionTests {
    @Test func commitmentUsesItsOwnProtectedBlockButBlocksOtherWork() throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let start = try #require(calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day))
        let now = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day))
        let model = LifeModelValidator.compileLocally(from: "### Gym\n**6:30 PM – 8:00 PM**")
        let gym = LifeTask(id: "gym", title: "Gym", estimatedMinutes: 90,
                           scheduledDate: day, scheduledTime: start,
                           tags: [LifeModel.commitmentTaskTag, model.commitmentID(for: "Gym")],
                           schedulingMode: .fixedTime)
        let work = LifeTask(id: "work", title: "Write meeting notes", estimatedMinutes: 30,
                            scheduledDate: day, scheduledTime: start)
        let result = DayScheduleReconciler.reconcile(tasks: [gym, work], on: day, model: model, now: now)
        let savedGym = try #require(result.tasks.first { $0.id == gym.id })
        #expect(savedGym.status.isActive)
        #expect(savedGym.scheduledTime == start)
        let gymInterval = try #require(TaskScheduleInterval.window(for: savedGym, on: day))
        let savedWork = try #require(result.tasks.first { $0.id == work.id })
        if let workInterval = TaskScheduleInterval.window(for: savedWork, on: day) {
            #expect(!gymInterval.overlaps(workInterval))
        }
    }

    private func fixture() throws -> (SimulationStore, TasksViewModel) {
        let service = GLMService()
        service.debugCompleteHandler = { _, _ in "{}" }
        let store = try SimulationStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("lookafter-regression-\(UUID())"),
            now: Calendar.current.startOfDay(for: Date())
        )
        return (store, TasksViewModel(
            taskRepo: store, decomposer: TaskDecomposer(glmService: service),
            autoFiller: TaskAutoFiller(glmService: service), taskImporter: TaskImporter(glmService: service),
            semanticAnalyzer: TaskSemanticAnalyzer(glmService: service)
        ))
    }

    @Test func editingProjectStepDoesNotRewriteGoal() async throws {
        let (store, vm) = try fixture()
        let plan = MultiDayTaskPlanner.plan(title: "Prepare launch report", dayCount: 5,
                                          userId: "test", startDate: store.now)
        try await vm.createMultiDayTasksAndAwait(plan: plan)
        vm.refreshFromLocal(userId: "test")
        var step = try #require(plan.slices.first)
        step.title = "Collect customer feedback"
        step.priority = .high
        #expect(await vm.scheduleMutation.persist(step, userId: "test", reconcileSchedule: false))
        let parent = try #require(store.localAllTasks(for: "test").first { $0.id == plan.parent.id })
        #expect(parent.title == plan.parent.title)
        #expect(parent.estimatedMinutes == plan.parent.estimatedMinutes)
        #expect(parent.priority == plan.parent.priority)
    }

    @Test func completedTaskCannotBeReopenedByLaterAIMutation() async throws {
        let (store, vm) = try fixture()
        let task = LifeTask(id: "done", title: "Draft notes", scheduledDate: store.now, userId: "test")
        try await store.create(task)
        vm.refreshFromLocal(userId: "test")
        var meds: [Medication] = []
        ScheduleMutationIdempotencyStore.shared.reset()
        _ = await PlanMutationApplier().apply(
            mutations: [PlanMutation(kind: .completeTask, taskID: task.id),
                        PlanMutation(kind: .deferTask, taskID: task.id)],
            tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: "test",
            medications: &meds, deferReconcile: true, now: store.now
        )
        #expect(store.localAllTasks(for: "test").first?.status == .completed)
    }

    @Test func replanApplyReportsFailedWrite() async throws {
        let (store, vm) = try fixture()
        let task = LifeTask(id: "persist", title: "Draft notes", scheduledDate: store.now, userId: "test")
        try await store.create(task)
        vm.refreshFromLocal(userId: "test")
        store.failNextWrite = true
        let planningVM = ExecutivePlanningViewModel()
        let saved = await planningVM.applyReplanResult(
            DayReplanResult(summary: "Defer", scheduleChanges: [.init(taskID: task.id, deferToTomorrow: true)]),
            now: store.now, tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: "test",
            refreshContext: {}, reconcileSchedule: false
        )
        #expect(saved == false)
        #expect(planningVM.errorMessage != nil)
        #expect(planningVM.isApplyingPlan == false)
        #expect(store.localAllTasks(for: "test").first?.scheduledDate == store.now)
    }

    @Test func duplicateReplanInstructionsHaveOneFinalOutcome() {
        let result = DayReplanResult(summary: "Revised plan", scheduleChanges: [
            .init(taskID: "same", startHour: 11, startMinute: 0),
            .init(taskID: "other", startHour: 12, startMinute: 0),
            .init(taskID: "same", deferToTomorrow: true)
        ])
        #expect(result.effectiveChanges().count == 2)
        #expect(result.effectiveChanges().last?.deferToTomorrow == true)
    }

    @Test func skippedRoutineIsNotReprojected() {
        let day = Calendar.current.startOfDay(for: Date())
        let template = LifeTask(id: "template", title: "Read notes", recurrence: .daily,
                                userId: "test", isRecurrenceTemplate: true)
        var skipped = TaskRecurrenceEngine.makeOccurrence(from: template, template: template, scheduledDate: day)
        skipped.status = .skipped
        #expect(TaskRecurrenceEngine.timelineProjections(for: [template, skipped], on: day).isEmpty)
    }

    @Test func weeklyOccurrenceMovedToAnotherWeekdaySurvivesRefresh() async throws {
        let (store, vm) = try fixture()
        let calendar = Calendar.current
        let day = store.now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let template = LifeTask(id: "weekly", title: "Review notes", recurrence: .weekly,
                                createdAt: day, userId: "test", isRecurrenceTemplate: true)
        let occurrence = TaskRecurrenceEngine.makeOccurrence(from: template, template: template, scheduledDate: day)
        try await store.create(template)
        try await store.create(occurrence)
        vm.refreshFromLocal(userId: "test")
        let deferred = vm.scheduleMutation.deferredTask(occurrence, from: day)
        #expect(await vm.scheduleMutation.persist(deferred, userId: "test", reconcileSchedule: false))
        await vm.syncRecurringSchedule(userId: "test", force: true, localOnly: true, now: tomorrow)
        let rows = store.localAllTasks(for: "test")
        let moved = try #require(rows.first { $0.id == occurrence.id })
        #expect(moved.status.isActive)
        #expect(moved.scheduledDate == tomorrow)
        #expect(moved.recurrenceOccurrenceDate == day)
        #expect(moved.isActionableToday(allTasks: rows, referenceDate: tomorrow))
        #expect(TaskRecurrenceEngine.missingOccurrences(for: rows, on: day).isEmpty)
        #expect(TaskRecurrenceEngine.timelineProjections(for: rows, on: day).isEmpty)
        #expect(rows.first { $0.id == template.id }?.recurrence == .weekly)
    }

    @Test func malformedAIProjectDaysStayInsideAgreedLength() {
        let plan = MultiDayTaskPlanner.plan(from: MultiDayPlanDraft(
            title: "Draft report", dayCount: 3, slices: [
                .init(dayIndex: -1, title: "Yesterday", estimatedMinutes: 20),
                .init(dayIndex: 0, title: "First", estimatedMinutes: 20),
                .init(dayIndex: 0, title: "Duplicate", estimatedMinutes: 20),
                .init(dayIndex: 80, title: "Much later", estimatedMinutes: 20)
            ]
        ), userId: "test")
        #expect(plan.slices.count == 3)
        #expect(Set(plan.slices.compactMap(\.scheduledDate)).count == 3)
        #expect(plan.slices.contains { $0.title == "Yesterday" || $0.title == "Much later" || $0.title == "Duplicate" } == false)
    }

    @Test func cancelledAIReplanDoesNotReturnAnApplyableFallback() async throws {
        let service = GLMService()
        service.debugSendMessageHandler = { _, _, _, _ in throw CancellationError() }
        let context = PlanningConversationContext(userName: "Test", tasks: [], timelineItems: [],
                                                  medications: [], availableMinutes: 60, energyPercent: 60)
        await #expect(throws: CancellationError.self) {
            _ = try await DayReplanEngine(glmService: service).replan(
                context: DayReplanContext(planningContext: context, completedTasks: [])
            )
        }
    }

    @Test func recurringCreateAwaitsPersistenceAndRollsBackPartialSeries() async throws {
        let (store, vm) = try fixture()
        let task = LifeTask(id: "create-series", title: "Read notes", scheduledDate: store.now,
                            recurrence: .daily, createdAt: store.now, userId: "test")
        store.writesBeforeFailure = 1
        await #expect(throws: (any Error).self) {
            try await vm.createTaskAndAwait(task)
        }
        #expect(store.localAllTasks(for: "test").isEmpty)
        try await vm.createTaskAndAwait(task)
        #expect(store.localAllTasks(for: "test").count == 2)
    }

    @Test func replanPersistsSnappedTimeAndPreservesCompletedAndFutureTasks() async throws {
        let (store, vm) = try fixture()
        let day = store.now
        let clock = { (hour: Int) in Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)! }
        let blocker = LifeTask(id: "fixed", title: "Client call", estimatedMinutes: 60,
                               scheduledDate: day, scheduledTime: clock(11), schedulingMode: .fixedTime, userId: "test")
        let task = LifeTask(id: "move", title: "Draft notes", estimatedMinutes: 15,
                            scheduledDate: day, scheduledTime: clock(14), userId: "test")
        let done = LifeTask(id: "completed", title: "Sent report", status: .completed,
                            scheduledDate: day, completedAt: day, userId: "test")
        let tomorrow = LifeTask(id: "future", title: "Tomorrow notes",
                                scheduledDate: Calendar.current.date(byAdding: .day, value: 1, to: day), userId: "test")
        for row in [blocker, task, done, tomorrow] { try await store.create(row) }
        vm.refreshFromLocal(userId: "test")
        let result = DayReplanResult(summary: "Replan", scheduleChanges: [
            .init(taskID: task.id, startHour: 11, startMinute: 0),
            .init(taskID: done.id, deferToTomorrow: true),
            .init(taskID: tomorrow.id, startHour: 13, startMinute: 0),
            .init(taskID: "hallucinated", startHour: 15, startMinute: 0)
        ])
        _ = await ExecutivePlanningViewModel().applyReplanResult(
            result, now: clock(10), tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: "test",
            refreshContext: {}, reconcileSchedule: false
        )
        let rows = store.localAllTasks(for: "test")
        #expect(rows.first { $0.id == task.id }?.scheduledTime == clock(12))
        #expect(rows.first { $0.id == done.id }?.status == .completed)
        #expect(rows.first { $0.id == tomorrow.id }?.scheduledDate == tomorrow.scheduledDate)
        #expect(rows.first { $0.id == tomorrow.id }?.scheduledTime == nil)
        #expect(rows.count == 4)
    }
}
