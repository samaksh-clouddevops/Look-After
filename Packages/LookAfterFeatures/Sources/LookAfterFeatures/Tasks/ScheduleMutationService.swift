import Foundation
import LookAfterCore

/// Single write gate for schedule mutations — persist, align constraints, reconcile, restamp.
@MainActor
public final class ScheduleMutationService {
    private unowned let viewModel: TasksViewModel

    public init(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    /// A daily habit already has its own next occurrence. Keep today's skipped
    /// identity so refresh cannot recreate it, rather than move it onto that row.
    public func deferredTask(_ task: LifeTask, from day: Date, calendar: Calendar = .current) -> LifeTask {
        var deferred = task
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        let source = TaskRecurrenceEngine.template(for: task, in: viewModel.schedulingContext)
        if task.parentTaskId != nil, !MultiDayTaskTags.isSlice(task),
           source.isRecurrenceTemplateTask, source.recurrenceOccurs(on: tomorrow, calendar: calendar) {
            deferred.status = .skipped
        } else {
            deferred.scheduledDate = tomorrow
            if task.parentTaskId != nil, source.isRecurrenceTemplateTask {
                deferred.recurrenceOccurrenceDate = task.recurrenceOccurrenceDate ?? task.scheduledDate ?? task.scheduledTime
            }
        }
        deferred.scheduledTime = nil
        deferred.scheduledEndTime = nil
        deferred.userPlacedScheduleAt = nil
        return deferred
    }

    /// Resolve a displayed occurrence without discarding the schedule the user just edited.
    public func persistTimelineEdit(_ edited: LifeTask, userId: String) async -> Bool {
        guard !userId.isEmpty else { return false }
        var target = edited
        if edited.id.hasPrefix("proj-")
            || viewModel.resolveTimelineTask(id: edited.id) == nil {
            do {
                target = try await viewModel.materializeTimelineTask(edited, userId: userId)
            } catch {
                viewModel.error = error.localizedDescription
                return false
            }
        }
        guard target.status.isActive else { return false }
        target.scheduledDate = edited.scheduledDate
        target.scheduledTime = edited.scheduledTime
        target.scheduledEndTime = edited.scheduledEndTime
        target.timeConstraint = edited.timeConstraint
        target.schedulingMode = edited.schedulingMode
        target.userPlacedScheduleAt = edited.userPlacedScheduleAt
        target.updatedAt = Date()
        return await persist(target, userId: userId, userPlaced: true)
    }

    /// Persists a task update and optionally reconciles when schedule fields changed.
    /// Returns `true` if this specific save succeeded. Callers that need to know whether
    /// *their* save succeeded (e.g. to decide whether to dismiss a sheet) should use this
    /// return value instead of reading `viewModel.error`, which is a long-lived flag set
    /// by many unrelated background operations and never reset on success.
    @discardableResult
    public func persist(
        _ task: LifeTask,
        userId: String,
        userPlaced: Bool = false,
        reconcileSchedule: Bool = true
    ) async -> Bool {
        var updated = TaskConstraintAlignment.align(task)
        ScheduleNormalization.normalizeFields(&updated)
        if userPlaced {
            TaskConstraintAlignment.markUserPlaced(&updated)
        }
        let previous = viewModel.tasks.first(where: { $0.id == task.id })
            ?? viewModel.completedToday.first(where: { $0.id == task.id })
            ?? viewModel.schedulingContext.first(where: { $0.id == task.id })
        if let previous, let oldDay = previous.scheduledDate ?? previous.scheduledTime,
           let newDay = updated.scheduledDate ?? updated.scheduledTime,
           !Calendar.current.isDate(oldDay, inSameDayAs: newDay),
           previous.parentTaskId != nil, !MultiDayTaskTags.isSlice(previous),
           TaskRecurrenceEngine.template(for: previous, in: viewModel.schedulingContext).isRecurrenceTemplateTask {
            updated.recurrenceOccurrenceDate = previous.recurrenceOccurrenceDate ?? oldDay
        }
        let succeeded = await viewModel.updateTaskAndPersist(updated)
        guard succeeded else { return false }
        let scheduleChanged = viewModel.scheduleFieldsChanged(from: previous, to: updated) || userPlaced
        if reconcileSchedule, scheduleChanged {
            let uid = userId.isEmpty ? updated.userId : userId
            if !uid.isEmpty {
                viewModel.requestDebouncedScheduleReconcile(userId: uid, immediate: true)
            }
            // SoT: schedule writes always restamp timeline + widgets (W2).
            viewModel.onScheduleWriteCommitted?()
        }
        return succeeded
    }

    /// Applies a day schedule change from the daily planner through the shared VM path.
    public func applyDayScheduleChanges(
        _ changes: [DayScheduleChange],
        userId: String,
        planningDay: Date,
        calendar: Calendar = .current
    ) async throws {
        let dayStart = calendar.startOfDay(for: planningDay)
        let taskByID = Dictionary.uniquingFirstValue(viewModel.tasks.map { ($0.id, $0) })
        let events = viewModel.calendarEventsProvider?(dayStart) ?? []
        let model = LifeModelStore.load()

        for change in changes {
            guard var task = taskByID[change.id] else { continue }
            if change.isFixed { continue }
            guard task.isSchedulerMovable,
                  let combined = calendar.combine(date: planningDay, timeFrom: change.proposedTime) else {
                continue
            }
            let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            let neighbors = viewModel.tasks.filter { $0.id != task.id && $0.status.isActive }
            let occupied = OccupiedDay.build(
                tasks: neighbors,
                calendarEvents: events,
                model: model,
                on: dayStart,
                calendar: calendar,
                excludingTaskID: task.id
            ).occupiedForPlacement(excludingTaskID: task.id)
            let placement = SchedulePlacementGuard.evaluate(
                proposedStart: combined,
                durationMinutes: duration,
                task: task,
                occupied: occupied,
                calendar: calendar,
                mode: .searchInBox,
                neighborTasks: neighbors
            )
            let start: Date
            switch placement {
            case .accepted(let date), .snapped(let date):
                start = date
            case .needsAI, .rejected:
#if DEBUG
                print("[Schedule] applyDayScheduleChanges rejected id=\(task.id.prefix(8))")
#endif
                throw ScheduleApplyError(taskTitle: task.title)
            }
            task.scheduledDate = dayStart
            task.scheduledTime = start
            task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
            TaskConstraintAlignment.markUserPlaced(&task)
            ScheduleNormalization.normalizeFields(&task)
            guard await viewModel.updateTaskAndPersist(task) else {
                throw ScheduleApplyError(taskTitle: task.title)
            }
        }

        await viewModel.syncScheduleAndReconcileToday(userId: userId)
        viewModel.onScheduleWriteCommitted?()
    }

    /// Removes a movable task from today's timeline (defer to tomorrow) and reconciles.
    @discardableResult
    public func removeFromTimelineToday(taskID: String, userId: String) async -> LifeTask? {
        guard var task = viewModel.tasks.first(where: { $0.id == taskID && $0.status.isActive }),
              task.isSchedulerMovable else { return nil }

        task = deferredTask(task, from: Date())
        guard await persist(task, userId: userId, reconcileSchedule: true) else { return nil }
        return task
    }

    /// Place a suggested slot onto a real task — must pass OccupiedDay guard (C5).
    @discardableResult
    public func placeSuggestedSlot(
        taskID: String,
        start: Date,
        userId: String,
        calendar: Calendar = .current
    ) async -> Bool {
        guard var task = viewModel.resolveTimelineTask(id: taskID),
              task.status.isActive,
              task.isSchedulerMovable else { return false }
        let day = calendar.startOfDay(for: start)
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let neighbors = viewModel.tasks.filter { $0.id != task.id && $0.status.isActive }
        let events = viewModel.calendarEventsProvider?(day) ?? []
        let occupied = OccupiedDay.build(
            tasks: neighbors,
            calendarEvents: events,
            model: LifeModelStore.load(),
            on: day,
            calendar: calendar,
            excludingTaskID: task.id
        ).occupiedForPlacement(excludingTaskID: task.id)
        let placement = SchedulePlacementGuard.evaluate(
            proposedStart: start,
            durationMinutes: duration,
            task: task,
            occupied: occupied,
            calendar: calendar,
            mode: .rejectOutsideBox,
            neighborTasks: neighbors
        )
        let resolved: Date
        switch placement {
        case .accepted(let date), .snapped(let date):
            resolved = date
        case .needsAI, .rejected:
            return false
        }
        task.scheduledDate = day
        task.scheduledTime = resolved
        task.scheduledEndTime = resolved.addingTimeInterval(TimeInterval(duration * 60))
        return await persist(task, userId: userId, userPlaced: true)
    }

    /// User drag-reschedule from timeline constraint VM.
    public func applyTimelineOffset(
        taskID: String,
        offsetMinutes: Int,
        userId: String
    ) async {
        guard offsetMinutes != 0,
              var task = viewModel.tasks.first(where: { $0.id == taskID }),
              task.timeConstraintValue != .anchored else { return }

        let calendar = Calendar.current
        let day = TaskRecurrenceEngine.creationDay(for: task, calendar: calendar)
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let base = task.scheduledTime
            ?? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
            ?? Date()
        let proposed = base.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        let neighbors = viewModel.tasks.filter { $0.id != task.id && $0.status.isActive }
        let events = viewModel.calendarEventsProvider?(day) ?? []
        let occupied = OccupiedDay.build(
            tasks: neighbors,
            calendarEvents: events,
            model: LifeModelStore.load(),
            on: day,
            calendar: calendar,
            excludingTaskID: task.id
        ).occupiedForPlacement(excludingTaskID: task.id)
        let placement = SchedulePlacementGuard.evaluate(
            proposedStart: proposed,
            durationMinutes: duration,
            task: task,
            occupied: occupied,
            calendar: calendar,
            mode: .rejectOutsideBox,
            neighborTasks: neighbors
        )
        let start: Date
        switch placement {
        case .accepted(let date), .snapped(let date):
            start = date
        case .needsAI, .rejected:
            return
        }
        task.scheduledTime = start
        task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
        task.scheduledDate = day
        TaskConstraintAlignment.markUserPlaced(&task)
        await persist(task, userId: userId, userPlaced: true, reconcileSchedule: true)
    }
}

private struct ScheduleApplyError: LocalizedError {
    let taskTitle: String
    var errorDescription: String? {
        "Couldn’t move \(taskTitle). Some earlier changes may already be saved. Review your schedule and try again."
    }
}
