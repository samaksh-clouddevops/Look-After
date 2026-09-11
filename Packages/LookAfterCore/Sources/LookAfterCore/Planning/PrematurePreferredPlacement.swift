import Foundation

/// Detects and clears clock slots parked *before* an upcoming preferred/fence.
///
/// Root cause companion to `DaySlotAllocator.resolveStart`: older builds fell back to
/// wall-clock `now` when preferred was blocked, so meals and evening tasks shared
/// the current minute. Reconcile clears those residue slots so allocation can retry.
public enum PrematurePreferredPlacement {

    /// Whether this task's persisted start is before its preferred/fence and should be cleared.
    public static func needsClear(
        _ task: LifeTask,
        on day: Date,
        now: Date = Date(),
        model: LifeModel? = nil,
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        calendar: Calendar = .current
    ) -> Bool {
        guard task.status.isActive,
              task.isSchedulerMovable,
              !TaskConstraintAlignment.isUserPlaced(task),
              let scheduledDate = task.scheduledDate,
              calendar.isDate(scheduledDate, inSameDayAs: day),
              let scheduledTime = task.scheduledTime,
              !TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar)
        else {
            return false
        }

        let enriched = TaskEphemeralityDefaults.enrich(task)
        if let box = enriched.temporalBoundingBox ?? TaskEphemeralityDefaults.boundingBox(for: task),
           !box.contains(start: scheduledTime, calendar: calendar) {
            return true
        }

        if let hours = SemanticPlacementSense.hourBounds(for: task, calendar: calendar) {
            let startMinutes = calendar.component(.hour, from: scheduledTime) * 60
                + calendar.component(.minute, from: scheduledTime)
            if startMinutes < hours.startMinutesFromMidnight {
                return true
            }
        }

        let preferred = preferredStart(for: task, on: day, model: model, profile: profile, calendar: calendar)
        guard let preferred, preferred > now else { return false }

        // Legacy allocator parked at wall-clock `now` when preferred was still ahead.
        guard scheduledTime < preferred else { return false }
        let nearNow = abs(scheduledTime.timeIntervalSince(now)) <= 90
        let clearlyEarly = preferred.timeIntervalSince(scheduledTime) >= 30 * 60
        return nearNow || clearlyEarly
    }

    /// Task IDs whose clocks should be cleared before re-allocation.
    public static func idsNeedingClear(
        in tasks: [LifeTask],
        on day: Date,
        now: Date = Date(),
        model: LifeModel? = nil,
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        calendar: Calendar = .current
    ) -> [String] {
        tasks
            .filter { needsClear($0, on: day, now: now, model: model, profile: profile, calendar: calendar) }
            .map(\.id)
    }

    /// Clears clock fields for premature placements; returns updated tasks.
    public static func clearingPrematureClocks(
        in tasks: [LifeTask],
        on day: Date,
        now: Date = Date(),
        model: LifeModel? = nil,
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let ids = Set(idsNeedingClear(in: tasks, on: day, now: now, model: model, profile: profile, calendar: calendar))
        guard !ids.isEmpty else { return tasks }
        return tasks.map { task in
            guard ids.contains(task.id) else { return task }
            var cleared = task
            cleared.scheduledTime = nil
            cleared.scheduledEndTime = nil
            cleared = TaskConstraintAlignment.align(cleared)
            cleared.updatedAt = now
            return cleared
        }
    }

    private static func preferredStart(
        for task: LifeTask,
        on day: Date,
        model: LifeModel?,
        profile: UserLifeProfile,
        calendar: Calendar
    ) -> Date? {
        if let anchor = RoutineScheduleAnchorResolver.preferredStart(
            for: task,
            on: day,
            model: model,
            profile: profile,
            calendar: calendar
        ) {
            return anchor
        }
        if let fromSense = SemanticPlacementSense.nearestPreferredStart(on: day, for: task, calendar: calendar) {
            return fromSense
        }
        if let hours = SemanticPlacementSense.hourBounds(for: task, calendar: calendar) {
            let dayStart = calendar.startOfDay(for: day)
            let hour = hours.startMinutesFromMidnight / 60
            let minute = hours.startMinutesFromMidnight % 60
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
        }
        return nil
    }
}
