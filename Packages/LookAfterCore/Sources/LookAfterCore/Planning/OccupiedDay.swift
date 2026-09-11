import Foundation

/// Unified occupancy for a calendar day — tasks + EventKit + life-model protected blocks.
/// Single builder for guard, allocator, cascade, and overlap checks (T-12 / SP-10).
public struct OccupiedDay: Sendable, Equatable {
    public var dayStart: Date
    /// All immovable + task intervals (sorted). Fixed peers use `cal.*` / `protected.*` ids.
    public var intervals: [TaskScheduleInterval]

    public init(dayStart: Date, intervals: [TaskScheduleInterval]) {
        self.dayStart = dayStart
        self.intervals = intervals.sorted { $0.start < $1.start }
    }

    public static let calendarIDPrefix = "cal."
    public static let protectedIDPrefix = "protected."

    public static func isFixedOccupant(taskID: String) -> Bool {
        taskID.hasPrefix(calendarIDPrefix) || taskID.hasPrefix(protectedIDPrefix)
    }

    /// Builds occupancy for placement / overlap.
    /// - Parameters:
    ///   - tasks: Active (and any other) tasks whose windows count.
    ///   - calendarEvents: EventKit peers for the day (timed always; all-day only when busy).
    ///   - model: Life model for gym / never_schedule protected blocks.
    ///   - excludingTaskID: Omit this task (the one being placed).
    ///   - includeAllDayBusy: C2 default — soft-occupy all-day busy events as full actionable day.
    public static func build(
        tasks: [LifeTask],
        calendarEvents: [BriefingCalendarEvent] = [],
        model: LifeModel? = nil,
        on day: Date,
        calendar: Calendar = .current,
        excludingTaskID: String? = nil,
        includeAllDayBusy: Bool = true,
        profile: UserLifeProfile? = nil
    ) -> OccupiedDay {
        let dayStart = calendar.startOfDay(for: day)
        var intervals: [TaskScheduleInterval] = []

        for task in tasks where task.status.isActive {
            if let excludingTaskID, task.id == excludingTaskID { continue }
            if let window = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) {
                intervals.append(window)
            }
        }

        intervals.append(contentsOf: calendarIntervals(
            from: calendarEvents,
            on: dayStart,
            calendar: calendar,
            includeAllDayBusy: includeAllDayBusy
        ))

        let windows = SchedulingWindows.from(
            profile: profile ?? UserLifeProfileStore.load(),
            lifeModel: model ?? LifeModelStore.load()
        )
        intervals.append(contentsOf: windows.protectedIntervals(on: dayStart, calendar: calendar))

        return OccupiedDay(dayStart: dayStart, intervals: intervals)
    }

    /// Fixed (calendar + protected) intervals only — seed cascade / allocator blocked set.
    public var fixedIntervals: [TaskScheduleInterval] {
        intervals.filter { Self.isFixedOccupant(taskID: $0.taskID) }
    }

    /// Task-only intervals.
    public var taskIntervals: [TaskScheduleInterval] {
        intervals.filter { !Self.isFixedOccupant(taskID: $0.taskID) }
    }

    /// True when any two distinct intervals overlap (task↔task or task↔fixed).
    public var hasOverlap: Bool {
        guard intervals.count > 1 else { return false }
        for i in 0..<intervals.count {
            for j in (i + 1)..<intervals.count where intervals[i].overlaps(intervals[j]) {
                return true
            }
        }
        return false
    }

    /// Occupied list for guard evaluation (excludes `excludingTaskID` if still present).
    public func occupiedForPlacement(excludingTaskID: String? = nil) -> [TaskScheduleInterval] {
        guard let excludingTaskID else { return intervals }
        return intervals.filter { $0.taskID != excludingTaskID }
    }

    // MARK: - Calendar → intervals

    public static func calendarIntervals(
        from events: [BriefingCalendarEvent],
        on day: Date,
        calendar: Calendar = .current,
        includeAllDayBusy: Bool = true
    ) -> [TaskScheduleInterval] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let actionableEnd = DayBoundaryPlanner.actionableDayEnd(on: dayStart, calendar: calendar)

        return events.compactMap { event in
            let id = "\(calendarIDPrefix)\(event.id)"
            if event.isAllDay {
                guard includeAllDayBusy, event.isBusy else { return nil }
                guard calendar.isDate(event.startDate, inSameDayAs: dayStart)
                    || (event.startDate < dayEnd && (event.endDate ?? event.startDate) > dayStart) else {
                    return nil
                }
                return TaskScheduleInterval(
                    taskID: id,
                    start: dayStart,
                    end: max(actionableEnd, dayStart.addingTimeInterval(60))
                )
            }

            let start = event.startDate
            let end = event.endDate ?? start.addingTimeInterval(3600)
            guard start < dayEnd, end > dayStart else { return nil }
            let clippedStart = max(start, dayStart)
            let clippedEnd = min(end, dayEnd)
            guard clippedEnd > clippedStart else { return nil }
            return TaskScheduleInterval(taskID: id, start: clippedStart, end: clippedEnd)
        }
    }
}
