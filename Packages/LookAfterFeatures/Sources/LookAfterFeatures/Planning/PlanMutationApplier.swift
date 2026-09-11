import Foundation
import LookAfterCore
import LookAfterAI

/// Applies structured plan mutations from Executive Planning conversations.
@MainActor
public struct PlanMutationApplier {
    private let calendar = Calendar.current
    private let placementJudge: TaskSemanticAnalyzer

    public init(placementJudge: TaskSemanticAnalyzer = TaskSemanticAnalyzer()) {
        self.placementJudge = placementJudge
    }

    public struct ApplyResult: Sendable {
        public var appliedCount: Int
        public var skippedReasons: [String]
        public var createdTaskIDs: [String]
        public var reusedTasks: [ReusedTaskNotice]

        public struct ReusedTaskNotice: Sendable, Equatable {
            public var requestedTitle: String
            public var existingTitle: String

            public init(requestedTitle: String, existingTitle: String) {
                self.requestedTitle = requestedTitle
                self.existingTitle = existingTitle
            }
        }

        public init(
            appliedCount: Int = 0,
            skippedReasons: [String] = [],
            createdTaskIDs: [String] = [],
            reusedTasks: [ReusedTaskNotice] = []
        ) {
            self.appliedCount = appliedCount
            self.skippedReasons = skippedReasons
            self.createdTaskIDs = createdTaskIDs
            self.reusedTasks = reusedTasks
        }
    }

    public func apply(
        mutations: [PlanMutation],
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        medications: inout [Medication],
        userMessage: String? = nil,
        lifeProfile: UserLifeProfile = UserLifeProfile(),
        deferReconcile: Bool = false,
        allowUserPlacedOverride: Bool = false
    ) async -> ApplyResult {
        var result = ApplyResult()
        let windows = SchedulingWindows.from(profile: lifeProfile)
        let dayStart = calendar.startOfDay(for: Date())
        let allTasks = tasksVM.schedulingContext
        let taskByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        let taskByTitle = Dictionary(
            allTasks.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pendingCreates: [PendingCreate] = []
        var schedulingPool = tasksScheduledToday(from: tasksVM.schedulingContext)
        let idempotency = ScheduleMutationIdempotencyStore.shared

        for mutation in mutations {
            let fingerprint = ScheduleMutationIdempotencyStore.fingerprint(mutation)
            if idempotency.wasApplied(fingerprint) {
                result.skippedReasons.append("Skipped duplicate change (already applied this session)")
                continue
            }
            switch mutation.kind {
            case .reuseTask:
                if let title = mutation.title,
                   let existing = resolvedExistingTask(mutation: mutation, taskByID: taskByID, taskByTitle: taskByTitle) {
                    result.reusedTasks.append(.init(requestedTitle: title, existingTitle: existing.title))
                }
                result.appliedCount += 1

            case .createTask:
                guard let title = mutation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    result.skippedReasons.append("Create task missing title")
                    continue
                }
                if isShoppingLike(title) {
                    _ = await modulesVM.addShoppingItem(name: title, category: "General")
                    result.appliedCount += 1
                    continue
                }
                if let existing = TaskDuplicateMatcher.findMatch(for: title, in: tasksVM.tasks) {
                    if let hour = mutation.startHour, let minute = mutation.startMinute,
                       var task = tasksVM.tasks.first(where: { $0.id == existing.id }),
                       !isScheduleLocked(task, allowUserPlacedOverride: allowUserPlacedOverride),
                       let scheduled = preferredStart(
                           hour: hour,
                           minute: minute,
                           windows: windows
                       ) {
                        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
                        let occupied = TaskScheduleInterval.intervals(
                            from: tasksVM.tasks.filter { $0.id != task.id && $0.status.isActive },
                            on: dayStart,
                            calendar: calendar
                        )
                        let neighbors = tasksVM.tasks.filter { $0.id != task.id && $0.status.isActive }
                        if let start = await resolvedStart(
                            proposed: scheduled,
                            durationMinutes: duration,
                            task: task,
                            occupied: occupied,
                            neighbors: neighbors
                        ) {
                            task.scheduledTime = start
                            task.scheduledDate = dayStart
                            task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
                            task.updatedAt = Date()
                            await tasksVM.scheduleMutation.persist(task, userId: userId, reconcileSchedule: !deferReconcile)
                            idempotency.markApplied(fingerprint)
                            result.appliedCount += 1
                            continue
                        }
                    }
                    result.reusedTasks.append(.init(requestedTitle: title, existingTitle: existing.title))
                    result.appliedCount += 1
                    continue
                }
                let minutes = TaskDurationPolicy.resolve(
                    aiMinutes: mutation.estimatedMinutes,
                    userMessage: userMessage,
                    phrase: title
                )
                var task = LifeTask(
                    title: title,
                    priority: mutation.priority ?? .medium,
                    status: .pending,
                    estimatedMinutes: minutes,
                    userId: userId
                )
                task.id = UUID().uuidString
                task.scheduledDate = calendar.startOfDay(for: Date())

                let preferredStart = preferredStart(
                    hour: mutation.startHour,
                    minute: mutation.startMinute,
                    windows: windows
                )
                pendingCreates.append(
                    PendingCreate(
                        task: task,
                        priority: mutation.priority ?? .medium,
                        preferredStart: preferredStart
                    )
                )

            case .rescheduleTask:
                guard var id = resolvedTaskID(mutation: mutation, taskByID: taskByID, taskByTitle: taskByTitle) else {
                    result.skippedReasons.append("Could not reschedule task")
                    continue
                }
                if id.hasPrefix("proj-"),
                   let projection = allTasks.first(where: { $0.id == id })
                    ?? taskByID[id] {
                    do {
                        let materialized = try await tasksVM.materializeTimelineTask(projection, userId: userId)
                        id = materialized.id
                    } catch {
                        result.skippedReasons.append("Could not materialize projected task")
                        continue
                    }
                }
                guard var task = tasksVM.schedulingContext.first(where: { $0.id == id })
                        ?? taskByID[id]
                        ?? allTasks.first(where: { $0.id == id }) else {
                    result.skippedReasons.append("Could not reschedule task")
                    continue
                }
                if isScheduleLocked(task, allowUserPlacedOverride: allowUserPlacedOverride) {
                    if task.userPlacedScheduleAt != nil && !allowUserPlacedOverride {
                        result.skippedReasons.append(
                            "Kept \"\(task.title)\" — you placed that time (approve the change to override)"
                        )
                    } else {
                        result.skippedReasons.append("Could not reschedule \"\(task.title)\" — schedule is locked")
                    }
                    continue
                }

                task.scheduledDate = dayStart

                let scheduled: Date?
                if let hour = mutation.startHour, let minute = mutation.startMinute {
                    scheduled = PlanningSchedulePolicy.validatedScheduleInWindows(
                        hour: hour,
                        minute: minute,
                        windows: windows
                    )
                } else {
                    let allocation = DaySlotAllocator.allocateAcrossWindows(
                        requests: [
                            DaySlotAllocator.Request.makingSense(of: task, on: dayStart, calendar: calendar)
                        ],
                        existingTasks: schedulingPool,
                        windows: windows,
                        on: dayStart
                    )
                    scheduled = allocation.first?.scheduledTime
                }

                guard let scheduled else {
                    result.skippedReasons.append("Could not reschedule \"\(task.title)\" — outside work hours or past")
                    continue
                }

                let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
                let occupied = TaskScheduleInterval.intervals(
                    from: schedulingPool.filter { $0.id != task.id },
                    on: dayStart,
                    calendar: calendar
                )
                let neighbors = schedulingPool.filter { $0.id != task.id }
                guard let placed = await resolvedStart(
                    proposed: scheduled,
                    durationMinutes: duration,
                    task: task,
                    occupied: occupied,
                    neighbors: neighbors
                ) else {
                    result.skippedReasons.append("Could not reschedule \"\(task.title)\" — that time does not make sense")
                    continue
                }

                task.scheduledTime = placed
                task.scheduledEndTime = placed.addingTimeInterval(TimeInterval(duration * 60))

                let others = schedulingPool.filter { $0.id != task.id }
                if let window = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar),
                   TaskScheduleInterval.intervals(from: others, on: dayStart, calendar: calendar)
                    .contains(where: { window.overlaps($0) }) {
                    if let shifted = shiftToAvoidOverlap(task: task, others: others, dayStart: dayStart, windows: windows) {
                        task = shifted
                    } else {
                        result.skippedReasons.append("Could not reschedule \"\(task.title)\" — overlaps an existing task")
                        continue
                    }
                }

                if allowUserPlacedOverride {
                    task.userPlacedScheduleAt = nil
                }
                await tasksVM.scheduleMutation.persist(task, userId: userId, reconcileSchedule: !deferReconcile)
                schedulingPool.removeAll { $0.id == task.id }
                schedulingPool.append(task)
                idempotency.markApplied(fingerprint)
                result.appliedCount += 1

            case .deferTask, .removeFromToday:
                guard let id = resolvedTaskID(mutation: mutation, taskByID: taskByID, taskByTitle: taskByTitle),
                      var task = taskByID[id] ?? tasksVM.tasks.first(where: { $0.id == id }),
                      !task.isFixedTimeEvent else {
                    result.skippedReasons.append("Could not defer task")
                    continue
                }
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
                task.scheduledDate = tomorrow
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                tasksVM.updateTask(task)
                result.appliedCount += 1
                Task {
                    if let script = await DeferralRecoveryCoordinator.shared.handleDeferral(task: task) {
                        NotificationCenter.default.post(
                            name: .deferralRecoveryScriptReady,
                            object: nil,
                            userInfo: ["script": script]
                        )
                    }
                }

            case .completeTask:
                guard let id = resolvedTaskID(mutation: mutation, taskByID: taskByID, taskByTitle: taskByTitle),
                      let task = taskByID[id] ?? tasksVM.tasks.first(where: { $0.id == id }) else {
                    result.skippedReasons.append("Could not complete task")
                    continue
                }
                await tasksVM.completeTask(task)
                result.appliedCount += 1

            case .markMedicationTaken:
                guard let medID = mutation.medicationID ?? matchMedicationID(title: mutation.title, medications: medications) else {
                    result.skippedReasons.append("Medication not found")
                    continue
                }
                if let idx = medications.firstIndex(where: { $0.id == medID }) {
                    medications[idx].isTaken = true
                    medications[idx].lastTakenAt = Date()
                    medications[idx].adherenceLog.append(Date())
                    persistMedications(medications)
                    result.appliedCount += 1
                }

            case .addShoppingItem:
                guard let name = mutation.shoppingItemName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    result.skippedReasons.append("Shopping item missing name")
                    continue
                }
                _ = await modulesVM.addShoppingItem(name: name, category: "General")
                result.appliedCount += 1

            case .captureNote:
                if let note = mutation.captureNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    let request = CaptureRequest(
                        text: note,
                        hintedIntent: .task,
                        source: .planning,
                        contextHints: CaptureContextHints(screen: "planning")
                    )
                    _ = await CaptureRouter.shared.route(request, userId: userId)
                }
                result.appliedCount += 1

            case .createMultiDayTask:
                guard let title = mutation.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                      let dayCount = mutation.dayCount else {
                    result.skippedReasons.append("Create multi-day task missing title or dayCount")
                    continue
                }
                var deadline: Date?
                if let iso = mutation.deadlineISO {
                    deadline = ISO8601DateFormatter().date(from: iso)
                }
                let draft = MultiDayPlanDraft(
                    title: title,
                    dayCount: dayCount,
                    lifeArea: inferLifeArea(from: mutation, userMessage: userMessage),
                    deadline: deadline,
                    slices: mutation.sliceDrafts ?? [],
                    reasoning: mutation.reason ?? ""
                )
                let plan = MultiDayTaskPlanner.plan(
                    from: draft,
                    userId: userId,
                    existingTasks: tasksVM.tasks + tasksVM.schedulingContext,
                    profile: lifeProfile
                )
                tasksVM.createMultiDayTasks(plan: plan)
                result.appliedCount += 1
                result.createdTaskIDs.append(plan.parent.id)
                result.createdTaskIDs.append(contentsOf: plan.slices.map(\.id))
            }
        }

        if !pendingCreates.isEmpty {
            let requests = pendingCreates.map {
                DaySlotAllocator.Request.makingSense(
                    of: $0.task,
                    on: dayStart,
                    preferredStart: $0.preferredStart,
                    calendar: calendar
                )
            }
            let allocations = DaySlotAllocator.allocateAcrossWindows(
                requests: requests,
                existingTasks: schedulingPool,
                windows: windows,
                on: dayStart
            )
            let allocationByID = Dictionary(uniqueKeysWithValues: allocations.map { ($0.id, $0.scheduledTime) })

            for pending in pendingCreates {
                var task = pending.task
                if let scheduledTime = allocationByID[task.id] {
                    task.scheduledTime = scheduledTime
                    let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
                    task.scheduledEndTime = scheduledTime.addingTimeInterval(TimeInterval(duration * 60))
                }
                tasksVM.createTask(task)
                schedulingPool.append(task)
                result.appliedCount += 1
                result.createdTaskIDs.append(task.id)
            }
        }

        if !deferReconcile {
            tasksVM.requestForceReplan()
            await tasksVM.reconcileTodaySchedule(userId: userId)
        }

        return result
    }

    private func resolvedStart(
        proposed: Date,
        durationMinutes: Int,
        task: LifeTask,
        occupied: [TaskScheduleInterval],
        neighbors: [LifeTask]
    ) async -> Date? {
        switch SchedulePlacementGuard.evaluate(
            proposedStart: proposed,
            durationMinutes: durationMinutes,
            task: task,
            occupied: occupied,
            calendar: calendar,
            mode: .rejectOutsideBox,
            neighborTasks: neighbors
        ) {
        case .accepted(let start), .snapped(let start):
            return start
        case .rejected:
            return nil
        case .needsAI(_, let start):
            return await judgeWithAI(
                task: task,
                proposedStart: start,
                durationMinutes: durationMinutes,
                neighbors: neighbors
            )
        }
    }

    private func judgeWithAI(
        task: LifeTask,
        proposedStart: Date,
        durationMinutes: Int,
        neighbors: [LifeTask]
    ) async -> Date? {
        let day = calendar.startOfDay(for: proposedStart)
        do {
            let judgment = try await placementJudge.judgePlacement(
                task: task,
                proposedStart: proposedStart,
                durationMinutes: durationMinutes,
                neighborTasks: neighbors,
                calendar: calendar
            )
            if judgment.allowed {
                return proposedStart
            }
            if let hour = judgment.suggestedStartHour, let minute = judgment.suggestedStartMinute,
               let suggested = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
                switch SemanticPlacementSense.judge(
                    SemanticPlacementSense.Input(
                        task: task,
                        proposedStart: suggested,
                        durationMinutes: durationMinutes,
                        occupied: TaskScheduleInterval.intervals(from: neighbors, on: day, calendar: calendar),
                        neighborTasks: neighbors,
                        calendar: calendar
                    )
                ) {
                case .makesSense, .needsAI:
                    return suggested
                case .doesNotMakeSense:
                    return nil
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private struct PendingCreate {
        var task: LifeTask
        var priority: Priority
        var preferredStart: Date?
    }

    private func tasksScheduledToday(from tasks: [LifeTask]) -> [LifeTask] {
        tasks.filter { task in
            guard let scheduledDate = task.scheduledDate, task.scheduledTime != nil else { return false }
            return calendar.isDateInToday(scheduledDate)
        }
    }

    private func preferredStart(
        hour: Int?,
        minute: Int?,
        windows: SchedulingWindows
    ) -> Date? {
        guard let hour, let minute else { return nil }
        return PlanningSchedulePolicy.validatedScheduleInWindows(
            hour: hour,
            minute: minute,
            windows: windows
        )
    }

    /// Gym, life commitments, and other locked clocks must not be moved by planning mutations.
    /// User-placed clocks are locked unless the user approved an override (P2).
    private func isScheduleLocked(_ task: LifeTask, allowUserPlacedOverride: Bool) -> Bool {
        if task.isLifeCommitmentTask || task.isFixedTimeEvent || OnboardingTaskSeeder.isActivityRoutineTitle(task.title) {
            return true
        }
        if task.userPlacedScheduleAt != nil && !allowUserPlacedOverride {
            return true
        }
        return false
    }

    private func resolvedExistingTask(
        mutation: PlanMutation,
        taskByID: [String: LifeTask],
        taskByTitle: [String: LifeTask]
    ) -> LifeTask? {
        if let id = mutation.taskID, let task = taskByID[id] { return task }
        if let title = mutation.title?.lowercased(), let task = taskByTitle[title] { return task }
        if let title = mutation.title {
            return TaskDuplicateMatcher.findMatch(for: title, in: Array(taskByID.values))
        }
        return nil
    }

    private func resolvedTaskID(
        mutation: PlanMutation,
        taskByID: [String: LifeTask],
        taskByTitle: [String: LifeTask]
    ) -> String? {
        if let id = mutation.taskID, taskByID[id] != nil { return id }
        if let title = mutation.title?.lowercased(), let task = taskByTitle[title] { return task.id }
        if let title = mutation.title, let match = TaskDuplicateMatcher.findMatch(for: title, in: Array(taskByID.values)) {
            return match.id
        }
        return mutation.taskID
    }

    private func matchMedicationID(title: String?, medications: [Medication]) -> String? {
        guard !medications.isEmpty else { return nil }
        guard let title else { return medications.count == 1 ? medications.first?.id : nil }
        let needle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 3 else { return medications.count == 1 ? medications.first?.id : nil }
        let matches = medications.filter {
            let name = $0.name.lowercased()
            return name == needle || name.contains(needle) || needle.contains(name)
        }
        guard matches.count == 1 else { return nil }
        return matches[0].id
    }

    private func persistMedications(_ medications: [Medication]) {
        MedicationStore.save(medications)
    }

    private func isShoppingLike(_ title: String) -> Bool {
        let lower = title.lowercased()
        let buyPrefixes = ["buy ", "get ", "pick up ", "pickup "]
        if buyPrefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        let keywords = ["groceries", "grocery list", "shopping list", "shopping trip"]
        return keywords.contains(where: { lower.contains($0) })
    }

    private func inferLifeArea(from mutation: PlanMutation, userMessage: String?) -> LifeArea {
        if let detection = userMessage.map({ MultiDayTaskDetector.detect(in: $0) }),
           let area = detection.inferredLifeArea {
            return area
        }
        return .work
    }

    private func shiftToAvoidOverlap(
        task: LifeTask,
        others: [LifeTask],
        dayStart: Date,
        windows: SchedulingWindows
    ) -> LifeTask? {
        guard var start = task.scheduledTime else { return nil }
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let protected = windows.protectedIntervals(on: dayStart, calendar: calendar)
        for _ in 0..<12 {
            start = start.addingTimeInterval(15 * 60)
            guard let validated = PlanningSchedulePolicy.validatedScheduleInWindows(
                hour: calendar.component(.hour, from: start),
                minute: calendar.component(.minute, from: start),
                windows: windows
            ) else { break }
            var candidate = task
            candidate.scheduledTime = validated
            candidate.scheduledEndTime = validated.addingTimeInterval(TimeInterval(duration * 60))
            guard let window = TaskScheduleInterval.window(for: candidate, on: dayStart, calendar: calendar) else { continue }
            let overlapsTasks = TaskScheduleInterval.intervals(from: others, on: dayStart, calendar: calendar)
                .contains(where: { window.overlaps($0) })
            let overlapsProtected = protected.contains { window.overlaps($0) }
            if !overlapsTasks && !overlapsProtected { return candidate }
        }
        return nil
    }
}
