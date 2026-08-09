import Foundation
import LookAfterCore

/// Single write gate for schedule mutations — persist, align constraints, reconcile.
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
        if reconcileSchedule, viewModel.scheduleFieldsChanged(from: previous, to: updated) || userPlaced {
            if userId.isEmpty {
                viewModel.requestDebouncedScheduleReconcile(userId: updated.userId, immediate: true)
            } else {
                viewModel.requestDebouncedScheduleReconcile(userId: userId, immediate: true)
            }
        }
    }

    /// Applies a day schedule change from the daily planner through the shared VM path.
    public func applyDayScheduleChanges(
        _ changes: [DayScheduleChange],
        userId: String,
        planningDay: Date,
        calendar: Calendar = .current
    ) async throws {
        let taskByID = Dictionary(uniqueKeysWithValues: viewModel.tasks.map { ($0.id, $0) })

        for change in changes {
            guard var task = taskByID[change.id] else { continue }
            if change.isFixed { continue }
            guard task.isSchedulerMovable,
                  let combined = calendar.combine(date: planningDay, timeFrom: change.proposedTime) else {
                continue
            }
            task.scheduledDate = calendar.startOfDay(for: planningDay)
            task.scheduledTime = combined
            let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            task.scheduledEndTime = combined.addingTimeInterval(TimeInterval(duration * 60))
            TaskConstraintAlignment.markUserPlaced(&task)
            ScheduleNormalization.normalizeFields(&task)
            await viewModel.updateTaskAndPersist(task)
        }

        await viewModel.syncScheduleAndReconcileToday(userId: userId)
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

    /// User drag-reschedule from timeline constraint VM.
    public func applyTimelineOffset(
        taskID: String,
        offsetMinutes: Int,
        userId: String
    ) async {
        guard offsetMinutes != 0,
              var task = viewModel.tasks.first(where: { $0.id == taskID }),
              task.timeConstraintValue != .anchored else { return }

        let delta = TimeInterval(offsetMinutes * 60)
        if let start = task.scheduledTime {
            task.scheduledTime = start.addingTimeInterval(delta)
        }
        if let end = task.scheduledEndTime {
            task.scheduledEndTime = end.addingTimeInterval(delta)
        }
        TaskConstraintAlignment.markUserPlaced(&task)
        await persist(task, userId: userId, userPlaced: true, reconcileSchedule: true)
    }
}
