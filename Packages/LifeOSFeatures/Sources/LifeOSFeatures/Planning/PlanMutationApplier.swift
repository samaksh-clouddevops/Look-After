import Foundation
import LifeOSCore

/// Applies structured plan mutations from Executive Planning conversations.
@MainActor
public struct PlanMutationApplier {
    private let calendar = Calendar.current

    public init() {}

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
        lifeProfile: UserLifeProfile = UserLifeProfile()
    ) async -> ApplyResult {
        var result = ApplyResult()
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: lifeProfile)
        let taskByID = Dictionary(uniqueKeysWithValues: tasksVM.tasks.map { ($0.id, $0) })
        let taskByTitle = Dictionary(
            tasksVM.tasks.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var pendingCreates: [PendingCreate] = []
        var schedulingPool = tasksScheduledToday(from: tasksVM.schedulingContext)

        for mutation in mutations {
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
                    result.reusedTasks.append(.init(requestedTitle: title, existingTitle: existing.title))
                    result.skippedReasons.append("Skipped duplicate: \"\(title)\" matches existing \"\(existing.title)\"")
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
                    workHours: workHours
                )
                pendingCreates.append(
                    PendingCreate(
                        task: task,
                        priority: mutation.priority ?? .medium,
                        preferredStart: preferredStart
                    )
                )

            case .rescheduleTask:
                guard let id = resolvedTaskID(mutation: mutation, taskByID: taskByID, taskByTitle: taskByTitle),
                      var task = taskByID[id] ?? tasksVM.tasks.first(where: { $0.id == id }),
                      !task.isFixedTimeEvent,
                      let hour = mutation.startHour, let minute = mutation.startMinute else {
                    result.skippedReasons.append("Could not reschedule task")
                    continue
                }
                guard let scheduled = PlanningSchedulePolicy.validatedSchedule(
                    hour: hour,
                    minute: minute,
                    workHours: workHours
                ) else {
                    result.skippedReasons.append("Could not reschedule \"\(task.title)\" — outside work hours or past")
                    continue
                }
                let dayStart = calendar.startOfDay(for: Date())
                task.scheduledDate = dayStart
                task.scheduledTime = scheduled
                let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
                task.scheduledEndTime = scheduled.addingTimeInterval(TimeInterval(duration * 60))

                let others = schedulingPool.filter { $0.id != task.id }
                if let window = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar),
                   TaskScheduleInterval.intervals(from: others, on: dayStart, calendar: calendar)
                    .contains(where: { window.overlaps($0) }) {
                    result.skippedReasons.append("Could not reschedule \"\(task.title)\" — overlaps an existing task")
                    continue
                }

                tasksVM.updateTask(task)
                schedulingPool.removeAll { $0.id == task.id }
                schedulingPool.append(task)
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
                tasksVM.updateTask(task)
                result.appliedCount += 1

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
                DaySlotAllocator.Request(
                    id: $0.task.id,
                    estimatedMinutes: $0.task.estimatedMinutes,
                    priority: $0.priority,
                    preferredStart: $0.preferredStart
                )
            }
            let allocations = DaySlotAllocator.allocate(
                requests: requests,
                existingTasks: schedulingPool,
                workHours: workHours
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

        await tasksVM.reconcileTodaySchedule(userId: userId)

        return result
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
        workHours: PlanningSchedulePolicy.WorkHours
    ) -> Date? {
        guard let hour, let minute else { return nil }
        return PlanningSchedulePolicy.validatedSchedule(
            hour: hour,
            minute: minute,
            workHours: workHours
        )
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
        guard let title else { return medications.first?.id }
        let needle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 3 else { return medications.first?.id }
        return medications.first {
            let name = $0.name.lowercased()
            return name == needle || name.contains(needle) || needle.contains(name)
        }?.id
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
}
