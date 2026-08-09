import Foundation

/// Decides when full day replanning is warranted vs repair-only passes.
public enum ReconcilePolicy {

    public struct Input: Sendable {
        public let tasks: [LifeTask]
        public let day: Date
        public let model: LifeModel?
        public let forceReplan: Bool

        public init(
            tasks: [LifeTask],
            day: Date,
            model: LifeModel? = LifeModelStore.load(),
            forceReplan: Bool = false
        ) {
            self.tasks = tasks
            self.day = day
            self.model = model
            self.forceReplan = forceReplan
        }
    }

    /// True when DaySchedulePlanner.plan + apply should run (not just repair passes).
    public static func needsFullReplan(
        _ input: Input,
        calendar: Calendar = .current
    ) -> Bool {
        if input.forceReplan { return true }

        let dayStart = calendar.startOfDay(for: input.day)
        let activePool = TaskScheduleQuery.scheduledActiveTasks(
            from: input.tasks,
            on: dayStart,
            calendar: calendar
        )

        if activePool.isEmpty {
            return hasUnslottedMovableTasks(input.tasks, on: dayStart, calendar: calendar)
        }

        let syncedPool = activePool.map {
            DayScheduleReconciler.syncCommitmentTimes($0, model: input.model, day: dayStart, calendar: calendar)
        }

        let commitmentDrift = zip(activePool, syncedPool).contains { original, synced in
            original.scheduledTime != synced.scheduledTime
                || original.scheduledEndTime != synced.scheduledEndTime
                || original.estimatedMinutes != synced.estimatedMinutes
        }
        if commitmentDrift { return true }
        if DayScheduleReconciler.hasOverlap(syncedPool, on: dayStart, calendar: calendar) { return true }

        return hasUnslottedMovableTasks(input.tasks, on: dayStart, calendar: calendar)
    }

    private static func hasUnslottedMovableTasks(
        _ tasks: [LifeTask],
        on dayStart: Date,
        calendar: Calendar
    ) -> Bool {
        tasks.contains { task in
            guard task.status.isActive, task.isSchedulerMovable else { return false }
            if task.tags.contains("daily-routine") || task.tags.contains("fixed") { return false }
            if TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: dayStart, calendar: calendar) {
                return true
            }
            guard task.scheduledTime == nil else { return false }
            if let scheduledDate = task.scheduledDate {
                return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
            }
            return calendar.isDateInToday(dayStart)
        }
    }
}
