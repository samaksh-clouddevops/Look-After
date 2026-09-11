import Foundation
import LookAfterCore

/// Single write gate for schedule mutations — persist, align constraints, reconcile, restamp.
@MainActor
public final class ScheduleMutationService {
    private unowned let viewModel: TasksViewModel

    public init(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    /// Persists a task update and optionally reconciles when schedule fields changed.
    public func persist(
        _ task: LifeTask,
        userId: String,
        userPlaced: Bool = false,
        reconcileSchedule: Bool = true
    ) async {
        var updated = TaskConstraintAlignment.align(task)
        ScheduleNormalization.normalizeFields(&updated)
        if userPlaced {
            TaskConstraintAlignment.markUserPlaced(&updated)
        }
        let previous = viewModel.tasks.first(where: { $0.id == task.id })
            ?? viewModel.completedToday.first(where: { $0.id == task.id })
        await viewModel.updateTaskAndPersist(updated)
        let scheduleChanged = viewModel.scheduleFieldsChanged(from: previous, to: updated) || userPlaced
        if reconcileSchedule, scheduleChanged {
            let uid = userId.isEmpty ? updated.userId : userId
            if !uid.isEmpty {
                viewModel.requestDebouncedScheduleReconcile(userId: uid, immediate: true)
            }
            // SoT: schedule writes always restamp timeline + widgets (W2).
            viewModel.onScheduleWriteCommitted?()
        }
    }

    /// Applies a day schedule change from the daily planner through the shared VM path.
    public func applyDayScheduleChanges(
        _ changes: [DayScheduleChange],
        userId: String,
        planningDay: Date,
        calendar: Calendar = .current
    ) async throws {
        let dayStart = calendar.startOfDay(for: planningDay)
        let taskByID = Dictionary(uniqueKeysWithValues: viewModel.tasks.map { ($0.id, $0) })
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
                continue
            }
            task.scheduledDate = dayStart
            task.scheduledTime = start
            task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
            TaskConstraintAlignment.markUserPlaced(&task)
            ScheduleNormalization.normalizeFields(&task)
            await viewModel.updateTaskAndPersist(task)
        }

        await viewModel.syncScheduleAndReconcileToday(userId: userId)
        viewModel.onScheduleWriteCommitted?()
    }

    /// Removes a movable task from today's timeline (defer to tomorrow) and reconciles.
    @discardableResult
    public func removeFromTimelineToday(taskID: String, userId: String) async -> LifeTask? {
        guard var task = viewModel.tasks.first(where: { $0.id == taskID && $0.status.isActive }),
              task.isSchedulerMovable else { return nil }

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        task.scheduledDate = tomorrow
        task.scheduledTime = nil
        task.scheduledEndTime = nil
        await persist(task, userId: userId, reconcileSchedule: true)
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
        await persist(task, userId: userId, userPlaced: true)
        return true
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
        let day = calendar.startOfDay(for: task.scheduledDate ?? Date())
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
