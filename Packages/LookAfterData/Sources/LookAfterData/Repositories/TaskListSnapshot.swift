import Foundation
import LookAfterCore

/// Cached active + completed-today task lists for fast UI hydration.
public struct TaskListSnapshot: Sendable, Equatable {
    public let active: [LifeTask]
    public let completedToday: [LifeTask]
    /// Recurrence master records — kept out of `active` but required for schedule checks.
    public let templates: [LifeTask]

    public init(active: [LifeTask], completedToday: [LifeTask], templates: [LifeTask] = []) {
        self.active = active
        self.completedToday = completedToday
        self.templates = templates
    }

    public static func make(
        from tasks: [LifeTask],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> TaskListSnapshot {
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let relevant = tasks.filter { task in
            if TaskRecurrenceEngine.isRecurrenceTemplate(task) { return true }
            switch task.status {
            case .pending, .inProgress, .paused, .completed, .deferred:
                return true
            case .superseded, .expired, .skipped:
                if let scheduledDate = task.scheduledDate {
                    return scheduledDate >= startOfDay
                }
                return task.updatedAt >= startOfDay
            }
        }
        let templates = relevant.filter(TaskRecurrenceEngine.isRecurrenceTemplate)
        let active = TaskScheduleQuery.activeTasksForToday(
            from: relevant,
            calendar: calendar,
            referenceDate: referenceDate
        )
            .sorted { $0.priority > $1.priority }
        let completedToday = relevant.filter { task in
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            guard task.status == .completed else { return false }
            let completionMoment = task.completedAt ?? task.updatedAt
            return completionMoment >= startOfDay
        }
        return TaskListSnapshot(active: active, completedToday: completedToday, templates: templates)
    }

    /// Active, completed-today, and recurrence templates for schedule validation.
    public var schedulingContext: [LifeTask] {
        active + completedToday + templates
    }
}

enum TaskMerge {
    /// Prefer the newer copy when the same task exists locally and remotely.
    static func merge(local: [LifeTask], remote: [LifeTask]) -> [LifeTask] {
        let deletedIDs = TaskDeletionRegistry.load()
        var byID = Dictionary(
            uniqueKeysWithValues: remote.compactMap { task in
                deletedIDs.contains(task.id) ? nil : (task.id, task)
            }
        )
        for task in local {
            guard !deletedIDs.contains(task.id) else { continue }
            if let existing = byID[task.id] {
                if task.updatedAt >= existing.updatedAt {
                    byID[task.id] = task
                }
            } else {
                byID[task.id] = task
            }
        }
        return byID.values.sorted { $0.createdAt > $1.createdAt }
    }
}

enum TaskPersistenceLog {
    static func create(_ task: LifeTask) {
#if DEBUG
        print("[Tasks] create id=\(task.id.prefix(8)) title=\"\(task.title)\"")
#endif
    }

    static func update(_ task: LifeTask) {
#if DEBUG
        print("[Tasks] update id=\(task.id.prefix(8)) status=\(task.status.rawValue)")
#endif
    }

    static func delete(_ id: String) {
#if DEBUG
        print("[Tasks] delete id=\(id.prefix(8))")
#endif
    }

    static func localSave(count: Int) {
#if DEBUG
        print("[Tasks] local save count=\(count)")
#endif
    }

    static func localLoad(count: Int, userId: String) {
#if DEBUG
        print("[Tasks] local load count=\(count) userId=\(userId.prefix(8))")
#endif
    }

    static func fetchStarted(source: String) {
#if DEBUG
        print("[Tasks] fetch started source=\(source)")
#endif
    }

    static func fetchFinished(count: Int, merged: Bool) {
#if DEBUG
        print("[Tasks] fetch finished count=\(count) merged=\(merged)")
#endif
    }

    static func fetchFailed(_ error: Error) {
#if DEBUG
        print("[Tasks] fetch failed: \(error.localizedDescription)")
#endif
    }

    static func filterApplied(active: Int, completedToday: Int) {
#if DEBUG
        print("[Tasks] filter active=\(active) completedToday=\(completedToday)")
#endif
    }
}
