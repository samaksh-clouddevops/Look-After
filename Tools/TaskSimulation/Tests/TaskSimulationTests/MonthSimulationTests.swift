import Foundation
import Testing
import LookAfterCore
import LookAfterData
@testable import LookAfterAI
@testable import LookAfterFeatures

@MainActor
@Suite(.serialized, .timeLimit(.minutes(3)))
struct MonthSimulationTests {
    private let calendar = Calendar.current
    private let user = "month-simulation"

    private func clock(_ hour: Int, _ minute: Int = 0, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func store(on day: Date) throws -> SimulationStore {
        try SimulationStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("lookafter-month-\(UUID())"),
            now: day
        )
    }

    private func glm(offline: Bool = true) -> GLMService {
        let service = GLMService.makeForTesting(keyManager: GLMKeyManager(
            secretStore: InMemorySecretStore(), metadataKey: "simulation.\(UUID())"
        ))
        service.debugCompleteHandler = { _, _ in "{}" }
        service.debugSendMessageHandler = { _, _, _, _ in
            if offline { throw GLMServiceError.noKeysConfigured }
            return #"{"summary":"Keep the important deadline first","scheduleChanges":[]}"#
        }
        return service
    }

    private func viewModel(_ store: SimulationStore, glm: GLMService) -> TasksViewModel {
        TasksViewModel(
            taskRepo: store, decomposer: TaskDecomposer(glmService: glm),
            autoFiller: TaskAutoFiller(glmService: glm), taskImporter: TaskImporter(glmService: glm),
            semanticAnalyzer: TaskSemanticAnalyzer(glmService: glm)
        )
    }

    private func context(tasks: [LifeTask], now: Date, trigger: DayReplanTrigger = .generic) -> DayReplanContext {
        DayReplanContext(planningContext: PlanningConversationContext(
            userName: "Avery", tasks: tasks, timelineItems: [], medications: [],
            availableMinutes: 240, energyPercent: 65, lifeProfile: UserLifeProfile(), now: now
        ), completedTasks: tasks.filter { $0.status == .completed }, trigger: trigger)
    }

    @Test func returningAfterThreeMissedDaysCleansEveryMissedDay() {
        let today = calendar.startOfDay(for: Date())
        let oldDay = calendar.date(byAdding: .day, value: -4, to: today)!
        var task = LifeTask(id: "missed", title: "Morning routine", scheduledDate: oldDay, userId: user)
        task.expirationPolicy = .endOfDay
        let result = DayScheduleReconciler.sweepDayBoundary(
            tasks: [task], from: today.addingTimeInterval(-86400), to: today, now: clock(10, on: today)
        )
        #expect(result.tasks.first?.status == .skipped)
    }

    @Test func unfinishedProjectStepSurvivesMidnight() {
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        var step = LifeTask(
            id: "step", title: "Draft report", scheduledDate: yesterday,
            tags: [MultiDayTaskTags.slice], parentTaskId: "project", userId: user
        )
        step.expirationPolicy = .infinite
        step.collisionStrategy = .allowMultiple
        let result = DayScheduleReconciler.sweepDayBoundary(tasks: [step], from: yesterday, to: today)
        #expect(result.tasks.first?.status.isActive == true)
        #expect(result.tasks.first?.parentTaskId == "project")
    }

    @Test func failedAIChangeReportsFailureAndCanBeRetried() async throws {
        let day = calendar.startOfDay(for: Date())
        let storage = try store(on: day)
        let service = glm()
        let vm = viewModel(storage, glm: service)
        let task = LifeTask(id: "retry", title: "Draft notes", scheduledDate: day, userId: user)
        try await storage.create(task)
        vm.refreshFromLocal(userId: user)
        let mutation = PlanMutation(kind: .deferTask, taskID: task.id)
        var meds: [Medication] = []
        ScheduleMutationIdempotencyStore.shared.reset()
        storage.failNextWrite = true
        let failed = await PlanMutationApplier().apply(
            mutations: [mutation], tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: user,
            medications: &meds, deferReconcile: true, now: clock(10, on: day)
        )
        #expect(failed.appliedCount == 0)
        #expect(failed.skippedReasons.isEmpty == false)
        #expect(storage.localAllTasks(for: user).first?.scheduledDate == day)
        let retry = await PlanMutationApplier().apply(
            mutations: [mutation], tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: user,
            medications: &meds, deferReconcile: true, now: clock(10, on: day)
        )
        #expect(retry.appliedCount == 1)
    }

    @Test func duplicateAIItemsInOneReplyCreateOneTask() async throws {
        let day = calendar.startOfDay(for: Date())
        let storage = try store(on: day)
        let vm = viewModel(storage, glm: glm())
        var meds: [Medication] = []
        ScheduleMutationIdempotencyStore.shared.reset()
        let result = await PlanMutationApplier().apply(
            mutations: [
                PlanMutation(kind: .createTask, title: "Draft quarterly notes", estimatedMinutes: 15),
                PlanMutation(kind: .createTask, title: "Draft quarterly notes", estimatedMinutes: 15)
            ], tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: user,
            medications: &meds, deferReconcile: true, now: clock(8, on: day)
        )
        #expect(result.createdTaskIDs.count == 1)
        #expect(storage.localAllTasks(for: user).count == 1)
    }

    @Test func urgentAdditionIsIncludedInOfflineReplan() async throws {
        let day = calendar.startOfDay(for: Date())
        let low = (0..<8).map {
            LifeTask(id: "low-\($0)", title: "Organize notes \($0)", priority: .low,
                     estimatedMinutes: 30, scheduledDate: day, userId: user)
        }
        let urgent = LifeTask(id: "urgent", title: "Submit important application", priority: .high,
                              estimatedMinutes: 30, scheduledDate: day, userId: user)
        let result = try await DayReplanEngine(glmService: glm()).replan(
            context: context(tasks: low + [urgent], now: clock(10, on: day))
        )
        #expect(result.scheduleChanges.contains { $0.taskID == urgent.id && !$0.deferToTomorrow })
        #expect(result.effectiveChanges().contains { $0.taskID == urgent.id && $0.deferToTomorrow } == false)
    }

    @Test(arguments: [18, 22, 23])
    func lateNightOfflineReplanTerminatesAndDefers(hour: Int) async throws {
        let day = calendar.startOfDay(for: Date())
        let task = LifeTask(id: "late", title: "Draft notes", estimatedMinutes: 45,
                            scheduledDate: day, userId: user)
        let result = try await DayReplanEngine(glmService: glm()).replan(
            context: context(tasks: [task], now: clock(hour, 30, on: day))
        )
        #expect(result.effectiveChanges().contains { $0.taskID == task.id && $0.deferToTomorrow })
        #expect(result.planVariants?.allSatisfy { variant in
            variant.scheduleChanges.allSatisfy { $0.deferToTomorrow }
        } == true)
    }

    @Test func AIProjectFailureRollsBackAndRetryUsesPlanningDay() async throws {
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let storage = try store(on: day)
        let vm = viewModel(storage, glm: glm())
        let mutation = PlanMutation(kind: .createMultiDayTask, title: "Prepare report", dayCount: 4)
        var meds: [Medication] = []
        ScheduleMutationIdempotencyStore.shared.reset()
        storage.writesBeforeFailure = 2
        let failed = await PlanMutationApplier().apply(
            mutations: [mutation], tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: user,
            medications: &meds, deferReconcile: true, now: clock(10, on: day)
        )
        #expect(failed.appliedCount == 0)
        #expect(failed.createdTaskIDs.isEmpty)
        #expect(storage.localAllTasks(for: user).isEmpty)
        let retry = await PlanMutationApplier().apply(
            mutations: [mutation], tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: user,
            medications: &meds, deferReconcile: true, now: clock(10, on: day)
        )
        #expect(retry.appliedCount == 1)
        #expect(retry.createdTaskIDs.count == 5)
        let slices = storage.localAllTasks(for: user).filter { MultiDayTaskTags.isSlice($0) }
        #expect(slices.map(\.scheduledDate).compactMap { $0 }.min() == day)
    }

    @Test func offlineReplanRespectsMeetingDurationAwayWindowAndTomorrow() async throws {
        let day = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        let meeting = LifeTask(id: "meeting", title: "Client meeting", estimatedMinutes: 90,
                               scheduledDate: day, scheduledTime: clock(11, on: day),
                               schedulingMode: .fixedTime, userId: user)
        let later = LifeTask(id: "tomorrow", title: "Tomorrow draft", scheduledDate: tomorrow, userId: user)
        let work = (0..<5).map {
            LifeTask(id: "work-\($0)", title: "Draft page \($0)", estimatedMinutes: 90,
                     scheduledDate: day, userId: user)
        }
        var ctx = context(tasks: [meeting, later] + work, now: clock(10, on: day), trigger: .goingOut)
        ctx.awayWindow = DayReplanAwayWindow(start: clock(14, on: day), end: clock(16, on: day))
        let result = try await DayReplanEngine(glmService: glm()).replan(context: ctx)
        #expect(result.scheduleChanges.contains { $0.taskID == meeting.id || $0.taskID == later.id } == false)
        var placed: [TaskScheduleInterval] = []
        for change in result.scheduleChanges where !change.deferToTomorrow {
            let hour = try #require(change.startHour)
            let start = clock(hour, change.startMinute ?? 0, on: day)
            let interval = TaskScheduleInterval(taskID: change.taskID, start: start, end: start.addingTimeInterval(90 * 60))
            #expect(interval.overlaps(.init(taskID: meeting.id, start: clock(11, on: day), end: clock(12, 30, on: day))) == false)
            #expect(interval.overlaps(.init(taskID: "away", start: clock(14, on: day), end: clock(16, on: day))) == false)
            #expect(placed.contains { interval.overlaps($0) } == false)
            #expect(interval.end <= clock(18, on: day))
            placed.append(interval)
        }
    }

    // One ordered lifecycle per test: app closures reconstruct the SQLite store and VM.
    // Three habits change which tasks are completed, skipped, or left unfinished.
    @Test(arguments: [0, 1, 2])
    func thirtyDaysOfTaskManagement(habit: Int) async throws {
        let origin = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        var storage = try store(on: origin)
        let service = glm()
        var vm = viewModel(storage, glm: service)
        var diary: [String] = []
        let missedDays: Set<Int> = habit == 2 ? [3, 8, 9, 18, 19, 20, 21, 22, 23, 24, 27] : [3, 8, 9, 18, 19, 20, 27]
        var projectIDs = Set<String>()
        var completedIDs = Set<String>()
        var actions = 0
        let template = LifeTask(
            id: "daily-reading", title: "Read 10 pages", estimatedMinutes: 15,
            scheduledTime: clock(17, on: origin), recurrence: .daily,
            userId: user, isRecurrenceTemplate: true
        )
        try await storage.create(template)

        for offset in 0..<30 {
            let day = calendar.date(byAdding: .day, value: offset, to: origin)!
            let now = clock(10, on: day)
            if missedDays.contains(offset) {
                diary.append("D\(offset + 1): app unopened; persisted work untouched")
                continue
            }
            // Reopen, including after a process/app update: no in-memory VM state survives.
            storage = try SimulationStore(directory: storage.directory, now: now)
            vm = viewModel(storage, glm: service)
            await vm.syncRecurringSchedule(userId: user, force: true, localOnly: true, now: now)
            var all = storage.localAllTasks(for: user)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
            let sweep = DayScheduleReconciler.sweepDayBoundary(
                tasks: all, from: calendar.date(byAdding: .day, value: -1, to: day)!, to: day, now: now
            )
            try await storage.updateMany(sweep.tasks.filter { sweep.changedTaskIDs.contains($0.id) })
            vm.refreshFromLocal(userId: user)

            if offset == 1 {
                let plan = MultiDayTaskPlanner.plan(title: "Prepare launch report", dayCount: 7,
                                                  userId: user, startDate: now)
                try await vm.createMultiDayTasksAndAwait(plan: plan)
                projectIDs = Set(plan.slices.map(\.id))
                actions += 1
            }

            all = storage.localAllTasks(for: user)
            let occurrence = try #require(all.first {
                $0.parentTaskId == template.id && $0.status.isActive
                    && $0.scheduledDate.map { calendar.isDate($0, inSameDayAs: day) } == true
            })
            // A merged duplicate from another device, then repeated refresh and move.
            if offset % 5 == 0 {
                var duplicate = occurrence
                duplicate.id = "duplicate-\(offset)"
                try await storage.create(duplicate)
                all = storage.localAllTasks(for: user)
                let stale = Set(TaskSeriesResolver.duplicateGroupNonKeeperIDs(
                    in: all, on: day, referenceDate: now
                ))
                for var task in all where stale.contains(task.id) {
                    task.status = .superseded
                    try await storage.update(task)
                }
                actions += 1
            }
            vm.refreshFromLocal(userId: user)
            var moved = try #require(storage.localAllTasks(for: user).first {
                $0.parentTaskId == template.id && $0.status.isActive && $0.scheduledDate == day
            })
            for minute in [15, 30] {
                moved.scheduledTime = clock(17, minute, on: day)
                moved.scheduledEndTime = clock(17, minute + 15, on: day)
                #expect(await vm.scheduleMutation.persist(moved, userId: user, userPlaced: true, reconcileSchedule: false))
                actions += 1
            }
            let reopened = try SimulationStore(directory: storage.directory, now: now)
            #expect(reopened.localAllTasks(for: user).first { $0.id == moved.id }?.scheduledTime == clock(17, 30, on: day))

            if (offset + habit) % 3 == 0 {
                #expect(await vm.completeTask(moved, now: now) != nil)
                completedIDs.insert(moved.id)
                if offset % 6 == 0 {
                    await vm.markIncomplete(moved)
                    #expect(await vm.completeTask(moved, now: now) != nil)
                    actions += 2
                }
                actions += 1
            }
            let urgent = LifeTask(
                id: "deadline-\(offset)", title: "Submit application \(offset)", priority: .high,
                estimatedMinutes: 15, scheduledDate: day, userId: user
            )
            try await vm.createTaskAndAwait(urgent)
            vm.refreshFromLocal(userId: user)
            let scriptedAI = habit == 2 && offset.isMultiple(of: 2)
            if scriptedAI {
                let response = "{\"summary\":\"Put the important application first\",\"scheduleChanges\":[{\"taskID\":\"\(urgent.id)\",\"startHour\":11,\"startMinute\":0}]}"
                service.debugSendMessageHandler = { _, _, _, _ in response }
            } else {
                service.debugSendMessageHandler = { _, _, _, _ in throw GLMServiceError.noKeysConfigured }
            }
            let result = try await DayReplanEngine(glmService: service).replan(
                context: context(tasks: vm.schedulingContext, now: now)
            )
            #expect(result.scheduleChanges.contains { $0.taskID == urgent.id && !$0.deferToTomorrow }, "D\(offset + 1): urgent task disappeared from replan")
            let planningVM = ExecutivePlanningViewModel()
            _ = await planningVM.applyReplanResult(
                result, now: now, tasksVM: vm, modulesVM: LifeModulesViewModel(), userId: user,
                refreshContext: {}, reconcileSchedule: false
            )
            actions += 2
            all = storage.localAllTasks(for: user)
            #expect(all.first { $0.id == urgent.id }?.scheduledTime != nil, "D\(offset + 1): priority plan was not saved")
            #expect(Set(all.map(\.id)).count == all.count, "D\(offset + 1): duplicate stored identity")
            #expect(projectIDs.isSubset(of: Set(all.map(\.id))), "D\(offset + 1): project step lost")
            #expect(all.first { MultiDayTaskTags.isRoot($0) }?.title == (projectIDs.isEmpty ? nil : "Prepare launch report"), "D\(offset + 1): goal rewritten by a step edit")
            #expect(all.filter { projectIDs.contains($0.id) }.allSatisfy { $0.status != .superseded }, "D\(offset + 1): unfinished project step retired")
            #expect(completedIDs.isSubset(of: Set(all.filter { $0.status == .completed }.map(\.id))), "D\(offset + 1): completion lost")
            #expect(TaskRecurrenceEngine.missingOccurrences(for: all, on: day).isEmpty, "D\(offset + 1): refresh would duplicate routine")
            let futureRows = all.filter { $0.parentTaskId == template.id && $0.scheduledDate == tomorrow && $0.status.isActive }
            #expect(futureRows.count == 1, "D\(offset + 1): tomorrow routine missing or duplicated")
            let events = DayPlateBuilder.events(from: all, now: now, referenceDay: day)
            #expect(events.filter { $0.title == template.title && !$0.isCompleted }.count <= 1, "D\(offset + 1): duplicate routine in timeline")
            diary.append("D\(offset + 1): reopen; cleanup; move twice; optional complete/undo; urgent addition; \(scriptedAI ? "scripted AI" : "offline") preview/apply; SQLite re-read (\(all.count) rows)")
        }
        diary.append("30 days; \(actions) user actions; habit \(habit); timezone \(calendar.timeZone.identifier)")
        Attachment.record(diary.joined(separator: "\n"), named: "month-habit-\(habit).txt")
        print("MONTH_SIMULATION: \(diary.last!)")
    }
}
