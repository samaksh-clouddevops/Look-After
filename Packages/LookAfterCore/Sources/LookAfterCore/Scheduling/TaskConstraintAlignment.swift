import Foundation

/// Aligns legacy `schedulingMode` with semantic `timeConstraint` and user-placement markers.
public enum TaskConstraintAlignment {

    /// Applies constraint rules when persisting or reconciling a task.
    public static func align(_ task: LifeTask) -> LifeTask {
        var aligned = task
        alignConstraintFields(&aligned)
        return aligned
    }

    public static func alignConstraintFields(_ task: inout LifeTask) {
        if task.isLifeCommitmentTask {
            if task.schedulingModeValue == .fixedTime || task.timeConstraintValue != .anchored {
                task.applyTimeConstraint(.anchored)
            }
        } else if task.tags.contains("daily-routine"),
                  OnboardingTaskSeeder.isMealRoutineTitle(task.title) {
            // Meals keep fixedTime display preference but shift on conflict.
            if task.timeConstraintValue != .flexible {
                task.applyTimeConstraint(.flexible)
            }
        } else if task.schedulingModeValue == .fixedTime, task.timeConstraint == nil {
            if task.tags.contains("daily-routine") || task.tags.contains("fixed") {
                task.applyTimeConstraint(.anchored)
            } else if task.userPlacedScheduleAt != nil {
                task.applyTimeConstraint(.flexible)
            } else {
                task.applyTimeConstraint(.flexible)
            }
        } else if task.timeConstraint != nil {
            task.schedulingMode = task.timeConstraintValue.asSchedulingMode
        }
    }

    /// Marks a user-initiated schedule placement so drift correction will not override it.
    public static func markUserPlaced(_ task: inout LifeTask, at date: Date = Date()) {
        task.userPlacedScheduleAt = date
        if task.timeConstraintValue != .anchored {
            task.applyTimeConstraint(.flexible)
        }
        task.updatedAt = date
    }

    public static func isUserPlaced(_ task: LifeTask) -> Bool {
        task.userPlacedScheduleAt != nil
    }
}
