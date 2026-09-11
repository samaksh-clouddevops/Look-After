import Foundation
import LookAfterCore

/// Applies user-approved day-audit fixes through the task store (physics still via reconcile).
@MainActor
public enum DayAuditApplier {

    public static func apply(
        acceptedFixes: [DayAuditFix],
        selectedPulls: [DayAuditPullCandidate],
        tasksVM: TasksViewModel,
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let day = calendar.startOfDay(for: now)

        for fix in acceptedFixes {
            switch fix.kind {
            case .shrinkTask:
                guard var task = tasksVM.tasks.first(where: { $0.id == fix.taskID }),
                      let minutes = fix.suggestedMinutes else { continue }
                task.estimatedMinutes = max(minutes, TaskDurationPolicy.minimumMinutes)
                if let start = task.scheduledTime {
                    task.scheduledEndTime = start.addingTimeInterval(TimeInterval(task.estimatedMinutes * 60))
                }
                task.updatedAt = now
                await tasksVM.updateTaskAndPersist(task)

            case .skipTask, .deferTask:
                guard let task = tasksVM.tasks.first(where: { $0.id == fix.taskID }) else { continue }
                _ = await ScheduleMutationService(viewModel: tasksVM).removeFromTimelineToday(
                    taskID: task.id,
                    userId: userId
                )

            case .pullParked, .pullYesterday:
                break
            }
        }

        if !selectedPulls.isEmpty {
            var cursor = now
            for pull in selectedPulls {
                switch pull.origin {
                case .parked, .fluid:
                    let entry = ParkedTaskQueueStore.shared.candidatesForReintegration(limit: 20)
                        .first(where: { $0.taskID == pull.taskID })
                    if let entry {
                        _ = ParkedTaskRecoveryService.shared.placeSelected(
                            [entry],
                            gapStart: cursor,
                            day: day,
                            userId: userId,
                            tasksVM: tasksVM,
                            now: now
                        )
                        cursor = cursor.addingTimeInterval(TimeInterval((pull.estimatedMinutes + 5) * 60))
                    }
                case .yesterday:
                    guard var task = tasksVM.localAllTasks(userId: userId).first(where: { $0.id == pull.taskID })
                            ?? tasksVM.tasks.first(where: { $0.id == pull.taskID }) else { continue }
                    task.scheduledDate = day
                    task.scheduledTime = nil
                    task.scheduledEndTime = nil
                    task.status = .pending
                    task.updatedAt = now
                    task = TaskConstraintAlignment.align(task)
                    await tasksVM.updateTaskAndPersist(task)
                }
            }
        }

        if !userId.isEmpty {
            await tasksVM.reconcileTodaySchedule(userId: userId, date: now, calendar: calendar)
        }
    }
}
