import Foundation

/// Validates and repairs same-day task schedules so no two tasks overlap.
public enum DayScheduleReconciler {

    public struct Result: Sendable {
        public var tasks: [LifeTask]
        public var changedTaskIDs: Set<String>
        public var conflictTaskIDs: Set<String>

        public init(
            tasks: [LifeTask] = [],
            changedTaskIDs: Set<String> = [],
            conflictTaskIDs: Set<String> = []
        ) {
            self.tasks = tasks
            self.changedTaskIDs = changedTaskIDs
            self.conflictTaskIDs = conflictTaskIDs
        }
    }

    /// Reconciles scheduled tasks on a single day — anchors fixed/commitment tasks, moves flexible conflicts.
    public static func reconcile(
        tasks: [LifeTask],
        on day: Date,
        model: LifeModel? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = 5
    ) -> Result {
        let dayStart = calendar.startOfDay(for: day)
        var scheduled = tasks.filter { task in
            guard task.status.isActive, task.scheduledTime != nil else { return false }
            guard let scheduledDate = task.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }

        guard scheduled.count > 1 else {
            var changedIDs = Set<String>()
            let synced = scheduled.map { task -> LifeTask in
                let updated = syncCommitmentTimes(task, model: model, day: dayStart, calendar: calendar)
                if updated.scheduledTime != task.scheduledTime
                    || updated.scheduledEndTime != task.scheduledEndTime
                    || updated.estimatedMinutes != task.estimatedMinutes {
                    changedIDs.insert(task.id)
                }
                return updated
            }
            return Result(tasks: merge(tasks, updates: synced), changedTaskIDs: changedIDs)
        }

        var working = scheduled.map { syncCommitmentTimes($0, model: model, day: dayStart, calendar: calendar) }
        var changedIDs = Set<String>()
        var conflictIDs = Set<String>()

        let sortedIndices = working.indices.sorted { lhs, rhs in
            immovabilityRank(working[lhs]) > immovabilityRank(working[rhs])
                || (immovabilityRank(working[lhs]) == immovabilityRank(working[rhs])
                    && (TaskScheduleInterval.window(for: working[lhs], on: dayStart, calendar: calendar)?.start ?? .distantFuture)
                    < (TaskScheduleInterval.window(for: working[rhs], on: dayStart, calendar: calendar)?.start ?? .distantFuture))
        }

        var anchored: [TaskScheduleInterval] = []

        for index in sortedIndices {
            var task = working[index]
            guard var interval = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) else { continue }

            if let conflict = anchored.first(where: { interval.overlaps($0) }) {
                if !canReconcileMove(task) {
                    conflictIDs.insert(task.id)
                    anchored.append(interval)
                    working[index] = task
                    continue
                }

                let newStart = conflict.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
                applyStart(newStart, to: &task, on: dayStart, calendar: calendar)
                guard let updated = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) else { continue }

                if anchored.contains(where: { updated.overlaps($0) }) {
                    if let openStart = findOpenStart(
                        after: conflict.end,
                        durationMinutes: updated.durationMinutes,
                        blocked: anchored,
                        bufferMinutes: bufferMinutes,
                        calendar: calendar
                    ) {
                        applyStart(openStart, to: &task, on: dayStart, calendar: calendar)
                    } else {
                        conflictIDs.insert(task.id)
                    }
                }

                if task.scheduledTime != scheduled[index].scheduledTime {
                    changedIDs.insert(task.id)
                }
                interval = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) ?? interval
            }

            anchored.append(interval)
            anchored.sort { $0.start < $1.start }
            working[index] = task
        }

        return Result(
            tasks: merge(tasks, updates: working),
            changedTaskIDs: changedIDs,
            conflictTaskIDs: conflictIDs
        )
    }

    /// Returns true when two tasks overlap on the same day.
    public static func hasOverlap(
        _ tasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let intervals = TaskScheduleInterval.intervals(from: tasks, on: day, calendar: calendar)
        guard intervals.count > 1 else { return false }
        for i in 0..<(intervals.count - 1) {
            if intervals[i].overlaps(intervals[i + 1]) { return true }
        }
        for i in 0..<intervals.count {
            for j in (i + 1)..<intervals.count where intervals[i].overlaps(intervals[j]) {
                return true
            }
        }
        return false
    }

    // MARK: - Commitment sync

    /// Snaps life-commitment tasks to their LifeModel block start/end when drifted.
    public static func syncCommitmentTimes(
        _ task: LifeTask,
        model: LifeModel?,
        day: Date,
        calendar: Calendar = .current
    ) -> LifeTask {
        guard task.isLifeCommitmentTask, let model else { return task }
        guard let commitment = model.commitments.first(where: {
            task.tags.contains(model.commitmentID(for: $0.title))
                || task.title.caseInsensitiveCompare($0.title) == .orderedSame
        }) else { return task }

        guard let blockLabel = commitment.preferredBlockLabel,
              let block = model.block(matching: blockLabel) else { return task }

        guard block.days.includes(day, calendar: calendar) else { return task }

        var updated = task
        guard let start = calendar.date(
            bySettingHour: block.startHour,
            minute: block.startMinute,
            second: 0,
            of: day
        ) else { return task }

        let endMinutes = block.startMinutesFromMidnight + commitment.defaultMinutes
        let endHour = endMinutes / 60
        let endMinute = endMinutes % 60
        let end = calendar.date(
            bySettingHour: min(endHour, 23),
            minute: endMinute,
            second: 0,
            of: day
        )

        updated.scheduledDate = day
        updated.scheduledTime = start
        updated.scheduledEndTime = end
        updated.estimatedMinutes = commitment.defaultMinutes
        if commitment.isNonNegotiable || block.protection == .neverSchedule || block.protection == .priorityOnly {
            updated.schedulingMode = .fixedTime
        }
        return updated
    }

    // MARK: - Private

    private static func canReconcileMove(_ task: LifeTask) -> Bool {
        if task.isSchedulerMovable { return true }
        // Legacy onboarding fixed meals can shift when they conflict with life commitments.
        return task.isFixedTimeEvent && !task.isLifeCommitmentTask
    }

    private static func immovabilityRank(_ task: LifeTask) -> Int {
        if task.isLifeCommitmentTask && task.isFixedTimeEvent && task.priority == .high { return 5 }
        if task.isLifeCommitmentTask && task.isFixedTimeEvent { return 4 }
        if task.isFixedTimeEvent { return 3 }
        if task.isLifeCommitmentTask { return 2 }
        return 1
    }

    private static func applyStart(
        _ start: Date,
        to task: inout LifeTask,
        on day: Date,
        calendar: Calendar
    ) {
        task.scheduledDate = day
        task.scheduledTime = start
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
    }

    private static func findOpenStart(
        after conflictEnd: Date,
        durationMinutes: Int,
        blocked: [TaskScheduleInterval],
        bufferMinutes: Int,
        calendar: Calendar
    ) -> Date? {
        var candidate = conflictEnd.addingTimeInterval(TimeInterval(bufferMinutes * 60))
        for _ in 0..<96 {
            let probeEnd = candidate.addingTimeInterval(TimeInterval(durationMinutes * 60))
            let overlaps = blocked.contains { blockedInterval in
                candidate < blockedInterval.end && blockedInterval.start < probeEnd
            }
            if !overlaps { return candidate }
            if let nextConflict = blocked.first(where: { candidate < $0.end && $0.start < probeEnd }) {
                candidate = nextConflict.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
            } else {
                candidate = calendar.date(byAdding: .minute, value: 15, to: candidate) ?? candidate
            }
        }
        return nil
    }

    private static func merge(_ original: [LifeTask], updates: [LifeTask]) -> [LifeTask] {
        let updateByID = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        return original.map { updateByID[$0.id] ?? $0 }
    }
}
