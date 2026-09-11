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
    /// Merge policy: tombstones win; then status monotonicity; then LWW on `updatedAt`.
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
                byID[task.id] = prefer(task, existing)
            } else {
                byID[task.id] = task
            }
        }
        return byID.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// Prefer terminal progress over clock-only LWW so a stale remote cannot un-complete a task.
    /// Prefer local schedule clocks when the local side has a newer user-placed stamp or
    /// local `updatedAt` is within 60s of remote (A4 / P6 default).
    static func prefer(_ a: LifeTask, _ b: LifeTask) -> LifeTask {
        let rankA = statusRank(a.status)
        let rankB = statusRank(b.status)
        if rankA != rankB {
            var winner = rankA > rankB ? a : b
            let loser = rankA > rankB ? b : a
            if winner.status == .completed, winner.completedAt == nil {
                winner.completedAt = loser.completedAt ?? winner.updatedAt
            }
            return winner
        }

        let newerByClock = a.updatedAt >= b.updatedAt ? a : b
        let olderByClock = a.updatedAt >= b.updatedAt ? b : a

        if let merged = preferScheduleFields(local: newerByClock, remote: olderByClock)
            ?? preferScheduleFields(local: olderByClock, remote: newerByClock) {
            return merged
        }
        return newerByClock
    }

    /// When `local` should keep its schedule fields over `remote`, returns local with remote non-schedule progress preserved as needed.
    private static func preferScheduleFields(local: LifeTask, remote: LifeTask) -> LifeTask? {
        let localPlaced = local.userPlacedScheduleAt
        let remotePlaced = remote.userPlacedScheduleAt
        if let lp = localPlaced, remotePlaced == nil || lp >= (remotePlaced ?? .distantPast) {
            return copySchedule(from: local, onto: remote.updatedAt > local.updatedAt ? withUpdatedAt(remote, local.updatedAt) : local)
        }
        let skew: TimeInterval = 60
        if abs(local.updatedAt.timeIntervalSince(remote.updatedAt)) <= skew,
           scheduleFingerprint(local) != scheduleFingerprint(remote) {
            // Near-simultaneous write: keep local schedule.
            return copySchedule(from: local, onto: remote.updatedAt > local.updatedAt ? withUpdatedAt(local, remote.updatedAt) : local)
        }
        // In-flight local dirty (C6): recent local schedule edit wins over cloud for a few seconds.
        let dirtyWindow: TimeInterval = 5
        if Date().timeIntervalSince(local.updatedAt) < dirtyWindow,
           scheduleFingerprint(local) != scheduleFingerprint(remote) {
            return copySchedule(from: local, onto: remote.updatedAt > local.updatedAt ? withUpdatedAt(local, remote.updatedAt) : local)
        }
        return nil
    }

    private static func withUpdatedAt(_ task: LifeTask, _ date: Date) -> LifeTask {
        var copy = task
        copy.updatedAt = date
        return copy
    }

    private static func scheduleFingerprint(_ task: LifeTask) -> String {
        [
            task.scheduledDate.map { String($0.timeIntervalSince1970) } ?? "-",
            task.scheduledTime.map { String($0.timeIntervalSince1970) } ?? "-",
            task.scheduledEndTime.map { String($0.timeIntervalSince1970) } ?? "-",
            task.userPlacedScheduleAt.map { String($0.timeIntervalSince1970) } ?? "-",
            task.timeConstraint?.rawValue ?? "-"
        ].joined(separator: "|")
    }

    private static func copySchedule(from source: LifeTask, onto base: LifeTask) -> LifeTask {
        var merged = base
        merged.scheduledDate = source.scheduledDate
        merged.scheduledTime = source.scheduledTime
        merged.scheduledEndTime = source.scheduledEndTime
        merged.userPlacedScheduleAt = source.userPlacedScheduleAt
        merged.timeConstraint = source.timeConstraint
        merged.schedulingMode = source.schedulingMode
        if source.updatedAt > merged.updatedAt {
            merged.updatedAt = source.updatedAt
        }
        return merged
    }

    private static func statusRank(_ status: TaskStatus) -> Int {
        switch status {
        case .pending: return 0
        case .inProgress: return 1
        case .paused: return 2
        case .deferred: return 3
        case .skipped: return 4
        case .expired: return 5
        case .superseded: return 6
        case .completed: return 7
        }
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
