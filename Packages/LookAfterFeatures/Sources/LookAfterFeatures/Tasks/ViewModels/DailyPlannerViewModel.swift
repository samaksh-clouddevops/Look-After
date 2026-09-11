import Foundation
import LookAfterAI
import LookAfterCore
import LookAfterData

/// Builds a practical, time-blocked plan for the current day. GLM may propose
/// the order and time blocks, while the local planner keeps the feature usable
/// offline or when an AI key has not been configured.
@MainActor
public final class DailyPlannerViewModel: ObservableObject {
    @Published public private(set) var todayTasks: [LifeTask] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var isScheduling = false
    @Published public var message: String?
    @Published public var error: String?
    @Published public var rescheduleProposal: DayRescheduleProposal?

    private let taskStore: TaskStore
    private let glm: GLMService
    private let calendar: Calendar
    private let calendarSyncService: CalendarSyncService
    private var lastHealthContext: String?
    private var planningDay: Date = Calendar.current.startOfDay(for: Date())

    public init(
        taskStore: TaskStore = .shared,
        glmService: GLMService = .shared,
        calendar: Calendar = .current,
        calendarSyncService: CalendarSyncService = CalendarSyncService()
    ) {
        self.taskStore = taskStore
        self.glm = glmService
        self.calendar = calendar
        self.calendarSyncService = calendarSyncService
    }

    public func loadToday(userId: String) async {
        planningDay = calendar.startOfDay(for: Date())
        await loadTasks(for: userId, on: planningDay, isToday: true)
    }

    public func loadTomorrow(userId: String) async {
        planningDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
            ?? calendar.startOfDay(for: Date())
        await loadTasks(for: userId, on: planningDay, isToday: false)
    }

    private func loadTasks(for userId: String, on day: Date, isToday: Bool) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let allTasks = try await taskStore.getAll(for: userId)
            try await createDueRecurringOccurrences(from: allTasks, userId: userId, on: day)
            let refreshed = try await taskStore.getAll(for: userId)
            todayTasks = refreshed
                .filter {
                    guard $0.status.isActive else { return false }
                    guard let scheduledDate = $0.scheduledDate else { return isToday && calendar.isDateInToday($0.createdAt) }
                    return calendar.isDate(scheduledDate, inSameDayAs: day)
                }
                .sorted(by: Self.sortBySchedule)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Builds an AI day plan preview without applying it.
    public func proposeDayReschedule(userId: String, healthContext: String? = nil) async {
        planningDay = calendar.startOfDay(for: Date())
        await proposeReschedule(userId: userId, healthContext: healthContext, dayLabel: "today")
    }

    public func proposeTomorrowReschedule(userId: String, healthContext: String? = nil) async {
        planningDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
            ?? calendar.startOfDay(for: Date())
        await loadTomorrow(userId: userId)
        await proposeReschedule(userId: userId, healthContext: healthContext, dayLabel: "tomorrow")
    }

    private func proposeReschedule(userId: String, healthContext: String?, dayLabel: String) async {
        guard !todayTasks.isEmpty else {
            message = dayLabel == "tomorrow" ? "No tasks scheduled for tomorrow yet." : "Add a task before replanning today."
            return
        }

        lastHealthContext = healthContext
        isScheduling = true
        error = nil
        defer { isScheduling = false }

        do {
            let tier: AIModelTier = TaskManagementPreferences.highQualitySchedulingEnabled ? .premium : .standard
            let modelName = glm.configuration.model(for: tier)
            let response = try await glm.complete(
                prompt: schedulingPrompt(healthContext: healthContext, dayLabel: dayLabel),
                systemPrompt: LookAfterPrompts.dailySchedulerSystem,
                tier: tier
            )
            let decoded = try decodeSuggestions(from: response)
            let allowedIDs = Set(schedulableFlexibleTasks().map(\.id))
            let suggestions = DayScheduleSuggestionValidator.validated(decoded, allowedTaskIDs: allowedIDs)
            let summary = dayLabel == "tomorrow"
                ? "AI organized tomorrow's flexible tasks around fixed commitments."
                : "AI reorganized your flexible tasks around fixed commitments."
            rescheduleProposal = buildProposal(
                from: suggestions,
                summary: summary,
                source: .ai(model: modelName)
            )
        } catch {
            rescheduleProposal = buildLocalProposal()
        }
    }

    public func addTask(
        title: String,
        minutes: Int,
        priority: Priority,
        recurrence: TaskRecurrence,
        userId: String
    ) async {
        let today = calendar.startOfDay(for: Date())

        do {
            if recurrence == .none {
                let task = LifeTask(
                    title: title,
                    priority: priority,
                    difficulty: minutes >= 60 ? .hard : .medium,
                    estimatedMinutes: minutes,
                    requiredEnergy: minutes >= 60 ? .high : .moderate,
                    scheduledDate: today,
                    userId: userId
                )
                try await taskStore.create(task)
                todayTasks.append(task)
            } else {
                let template = LifeTask(
                    title: title,
                    priority: priority,
                    difficulty: minutes >= 60 ? .hard : .medium,
                    estimatedMinutes: minutes,
                    requiredEnergy: minutes >= 60 ? .high : .moderate,
                    recurrence: recurrence,
                    userId: userId,
                    isRecurrenceTemplate: true
                )
                let occurrence = TaskRecurrenceEngine.makeOccurrence(
                    from: template,
                    template: template,
                    scheduledDate: today,
                    calendar: calendar
                )
                var mutableOccurrence = occurrence
                mutableOccurrence.userId = userId
                try await taskStore.create(template)
                try await taskStore.create(mutableOccurrence)
                todayTasks.append(mutableOccurrence)
            }

            todayTasks.sort(by: Self.sortBySchedule)
            message = recurrence == .none ? "Added to today." : "Added to today and set to repeat."
            NotificationCenter.default.post(name: .taskListDidChange, object: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Legacy entry point — opens the preview flow.
    public func scheduleToday(userId: String, healthContext: String? = nil) async {
        await proposeDayReschedule(userId: userId, healthContext: healthContext)
    }

    public func applyRescheduleProposal(userId: String, tasksViewModel: TasksViewModel? = nil) async {
        guard let proposal = rescheduleProposal else { return }
        let wasPlanningTomorrow = !calendar.isDateInToday(planningDay)
        isScheduling = true
        error = nil
        defer { isScheduling = false }

        do {
            if let tasksViewModel {
                try await tasksViewModel.scheduleMutation.applyDayScheduleChanges(
                    proposal.changes,
                    userId: userId,
                    planningDay: planningDay,
                    calendar: calendar
                )
            } else {
                try await apply(changes: proposal.changes)
            }
            try? await calendarSyncService.syncToCalendar(tasks: todayTasks)
            message = wasPlanningTomorrow ? "Tomorrow's plan is ready." : "Your updated plan is live."
            rescheduleProposal = nil
            NotificationCenter.default.post(name: .taskListDidChange, object: nil)
            if wasPlanningTomorrow {
                await loadTomorrow(userId: userId)
            } else {
                await loadToday(userId: userId)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func rejectRescheduleProposal() {
        rescheduleProposal = nil
        message = "Kept your current schedule."
    }

    public func regenerateRescheduleProposal(userId: String) async {
        if calendar.isDateInToday(planningDay) {
            await proposeDayReschedule(userId: userId, healthContext: lastHealthContext)
        } else {
            await proposeTomorrowReschedule(userId: userId, healthContext: lastHealthContext)
        }
    }

    public func complete(_ task: LifeTask) async {
        var completedTask = task
        completedTask.status = .completed
        completedTask.completedAt = Date()
        completedTask.actualMinutes = task.estimatedMinutes

        todayTasks.removeAll { $0.id == task.id }

        do {
            try await taskStore.update(completedTask)
            NotificationCenter.default.post(name: .taskListDidChange, object: nil)
        } catch {
            todayTasks.append(task)
            todayTasks.sort(by: Self.sortBySchedule)
            self.error = error.localizedDescription
        }
    }

    private func createDueRecurringOccurrences(from allTasks: [LifeTask], userId: String, on day: Date) async throws {
        for task in allTasks where TaskRecurrenceEngine.needsLegacyNormalization(task) {
            let (template, occurrence) = TaskRecurrenceEngine.normalizeLegacyRecurringTask(task)
            try await taskStore.create(template)
            try await taskStore.update(occurrence)
        }

        let refreshed = try await taskStore.getAll(for: userId)
        let missing = TaskRecurrenceEngine.missingOccurrences(for: refreshed, on: day, calendar: calendar)
            .filter { !$0.isLifeCommitmentTask }
        for var occurrence in missing {
            occurrence.userId = userId
            try await taskStore.create(occurrence)
        }
    }

    private func schedulingPrompt(healthContext: String?, dayLabel: String = "today") -> String {
        let profile = UserLifeProfileStore.load()
        let supplemental = PlanningPromptContextBuilder.supplementalContextBlock(
            analytics: nil,
            includeCalibration: true
        )
        let analyticsBlock = healthContext.map { "\($0)\n" } ?? ""
        let movable = schedulableFlexibleTasks()

        return """
        PLANNING TARGET: \(dayLabel.capitalized)
        \(PlanningPromptContextBuilder.temporalBlock(now: Date(), profile: profile, planningDay: planningDay))
        \(PlanningPromptContextBuilder.schedulingRulesBlock(planningDay: planningDay))
        \(PlanningPromptContextBuilder.dailyRoutineBlock())
        \(PlanningPromptContextBuilder.sleepBoundaryBlock(now: Date(), profile: profile))
        \(PlanningPromptContextBuilder.combinedLifeContextBlock(profile: profile))
        \(supplemental.isEmpty ? "" : "\(supplemental)\n")
        \(analyticsBlock)
        \(PlanningPromptContextBuilder.medicationsBlock(MedicationStore.load()))
        \(PlanningPromptContextBuilder.tasksBlock(todayTasks.filter(\.isFixedTimeEvent), style: .schedulingFixed))
        \(PlanningPromptContextBuilder.tasksBlock(movable, style: .schedulingFlexible))

        Return ONLY a JSON array matching this schema (use actual FLEXIBLE task ids):
        \(PlanningPromptContextBuilder.dailySchedulerResponseSchema)
        Include an entry for every FLEXIBLE task id listed above. Omit FIXED and life-commitment ids entirely.
        Never assign the same startHour/startMinute to two tasks. Stagger with 5+ minute gaps.
        Slot Morning review only when open capacity exists.
        """
    }

    private func schedulableFlexibleTasks() -> [LifeTask] {
        todayTasks.filter(\.isSchedulerMovable)
    }

    private func schedulingWindows() -> SchedulingWindows {
        SchedulingWindows.from(profile: UserLifeProfileStore.load())
    }

    private func workHoursForScheduling() -> PlanningSchedulePolicy.WorkHours {
        schedulingWindows().officeHours
    }

    private func schedulingReferenceNow() -> Date {
        calendar.isDateInToday(planningDay) ? Date() : planningDay
    }

    private func validatedProposedTime(hour: Int, minute: Int) -> Date? {
        PlanningSchedulePolicy.validatedScheduleInWindows(
            hour: hour,
            minute: minute,
            now: schedulingReferenceNow(),
            calendar: calendar,
            windows: schedulingWindows()
        ) ?? calendar.date(
            bySettingHour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: planningDay
        )
    }

    private func decodeSuggestions(from response: String) throws -> [DayScheduleSuggestion] {
        let clean = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try JSONDecoder().decode([RawScheduleSuggestion].self, from: Data(clean.utf8))
        return decoded.map {
            DayScheduleSuggestion(
                id: $0.id,
                startHour: $0.startHour,
                startMinute: $0.startMinute,
                reason: $0.reason ?? ""
            )
        }
    }

    private func buildProposal(
        from suggestions: [DayScheduleSuggestion],
        summary: String,
        source: DayPlanSource = .local
    ) -> DayRescheduleProposal {
        let taskByID = Dictionary(uniqueKeysWithValues: todayTasks.map { ($0.id, $0) })
        let movable = schedulableFlexibleTasks()
        var merged = suggestions.filter { suggestion in
            guard let task = taskByID[suggestion.id] else { return false }
            return task.isSchedulerMovable
        }
        let flexibleIDs = Set(movable.map(\.id))
        let suggestedIDs = Set(merged.map(\.id))
        if flexibleIDs.subtracting(suggestedIDs).isEmpty == false {
            merged += buildLocalSuggestions(for: Array(flexibleIDs.subtracting(suggestedIDs)), taskByID: taskByID)
        }

        var changes: [DayScheduleChange] = []

        for task in todayTasks where task.isFixedTimeEvent || task.isLifeCommitmentTask {
            let time = task.scheduledTime ?? planningDay
            changes.append(DayScheduleChange(
                id: task.id,
                taskTitle: task.title,
                previousTime: task.scheduledTime,
                proposedTime: calendar.combine(date: planningDay, timeFrom: time) ?? time,
                reason: task.isLifeCommitmentTask ? "Life commitment — time protected" : "Fixed commitment — time protected",
                isFixed: true,
                wasMoved: false
            ))
        }

        let sortedMerged = merged.sorted { lhs, rhs in
            let left = taskByID[lhs.id]?.priority ?? .medium
            let right = taskByID[rhs.id]?.priority ?? .medium
            if left != right { return left > right }
            return lhs.id < rhs.id
        }

        for suggestion in sortedMerged {
            guard let task = taskByID[suggestion.id], task.isSchedulerMovable else { continue }
            var proposed = validatedProposedTime(hour: suggestion.startHour, minute: suggestion.startMinute)
                ?? PlanningSchedulePolicy.schedulingCursorInWindows(
                    now: schedulingReferenceNow(),
                    calendar: calendar,
                    windows: schedulingWindows()
                )

            proposed = enforceBuffer(for: proposed, task: task, existing: changes, taskByID: taskByID)

            let previous = task.scheduledTime
            let moved = previous.map { abs($0.timeIntervalSince(proposed)) > 60 } ?? true
            changes.append(DayScheduleChange(
                id: task.id,
                taskTitle: task.title,
                previousTime: previous,
                proposedTime: proposed,
                reason: suggestion.reason.isEmpty ? "Better fit for your energy and priorities today" : suggestion.reason,
                isFixed: false,
                wasMoved: moved
            ))
        }

        changes.sort { lhs, rhs in
            if lhs.isFixed != rhs.isFixed { return lhs.isFixed && !rhs.isFixed }
            return lhs.proposedTime < rhs.proposedTime
        }

        return DayRescheduleProposal(
            summary: summary,
            changes: changes,
            suggestions: merged,
            source: source
        )
    }

    private func buildLocalProposal() -> DayRescheduleProposal {
        let movable = schedulableFlexibleTasks()
        let suggestions = buildLocalSuggestions(
            for: movable.map(\.id),
            taskByID: Dictionary(uniqueKeysWithValues: todayTasks.map { ($0.id, $0) })
        )
        return buildProposal(
            from: suggestions,
            summary: "\(UserFacingCopy.productName) created a focused local plan (AI planner unavailable).",
            source: .local
        )
    }

    private func buildLocalSuggestions(for ids: [String], taskByID: [String: LifeTask]) -> [DayScheduleSuggestion] {
        let windows = schedulingWindows()
        let requests = ids.compactMap { id -> DaySlotAllocator.Request? in
            guard let task = taskByID[id], task.isSchedulerMovable else { return nil }
            return DaySlotAllocator.Request.makingSense(of: task, on: planningDay, calendar: calendar)
        }
        let occupied = todayTasks.filter {
            guard let scheduledDate = $0.scheduledDate, $0.scheduledTime != nil else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: planningDay)
        }
        let allocations = DaySlotAllocator.allocateAcrossWindows(
            requests: requests,
            existingTasks: occupied,
            windows: windows,
            on: planningDay,
            now: schedulingReferenceNow(),
            calendar: calendar
        )
        return allocations.map { allocation in
            let components = PlanningSchedulePolicy.components(from: allocation.scheduledTime, calendar: calendar)
            return DayScheduleSuggestion(
                id: allocation.id,
                startHour: components.hour,
                startMinute: components.minute,
                reason: "Prioritized around fixed blocks and urgency"
            )
        }
    }

    private func apply(changes: [DayScheduleChange]) async throws {
        let taskByID = Dictionary(uniqueKeysWithValues: todayTasks.map { ($0.id, $0) })
        var scheduled: [LifeTask] = []

        for change in changes {
            guard var task = taskByID[change.id] else { continue }
            if change.isFixed {
                scheduled.append(task)
                continue
            }
            guard task.isSchedulerMovable,
                  let combined = combineTime(from: change.proposedTime, on: planningDay) else { continue }
            task.scheduledDate = calendar.startOfDay(for: planningDay)
            task.scheduledTime = combined
            try await taskStore.update(task)
            scheduled.append(task)
        }

        for task in todayTasks where !scheduled.contains(where: { $0.id == task.id }) {
            scheduled.append(task)
        }

        todayTasks = scheduled.sorted(by: Self.sortBySchedule)
    }

    private func enforceBuffer(
        for proposed: Date,
        task: LifeTask,
        existing: [DayScheduleChange],
        taskByID: [String: LifeTask]
    ) -> Date {
        var adjusted = proposed
        let buffer: TimeInterval = 5 * 60
        for change in existing {
            guard let other = taskByID[change.id], change.id != task.id else { continue }
            let otherEnd = change.proposedTime.addingTimeInterval(TimeInterval(other.estimatedMinutes * 60))
            if adjusted < otherEnd.addingTimeInterval(buffer) && adjusted >= change.proposedTime.addingTimeInterval(-buffer) {
                adjusted = otherEnd.addingTimeInterval(buffer)
            }
            let taskEnd = adjusted.addingTimeInterval(TimeInterval(task.estimatedMinutes * 60))
            if taskEnd > change.proposedTime.addingTimeInterval(-buffer) && adjusted <= change.proposedTime {
                adjusted = change.proposedTime.addingTimeInterval(-TimeInterval(task.estimatedMinutes * 60) - buffer)
            }
        }
        return validatedProposedTime(
            hour: calendar.component(.hour, from: adjusted),
            minute: calendar.component(.minute, from: adjusted)
        ) ?? adjusted
    }

    private func combineTime(from time: Date, on day: Date) -> Date? {
        calendar.combine(date: day, timeFrom: time)
    }

    private static func sortBySchedule(_ lhs: LifeTask, _ rhs: LifeTask) -> Bool {
        switch (lhs.scheduledTime, rhs.scheduledTime) {
        case let (left?, right?): return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.priority > rhs.priority
        }
    }
}

private struct RawScheduleSuggestion: Decodable {
    let id: String
    let startHour: Int
    let startMinute: Int
    let reason: String?
}

private enum DailyPlannerError: Error {
    case incompleteSchedule
}
