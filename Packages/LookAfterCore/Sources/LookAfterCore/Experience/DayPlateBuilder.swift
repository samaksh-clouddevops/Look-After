import Foundation

/// Canonical day-plate inputs for timeline, widgets, and draft plans.
///
/// Consumers should build from `localAllTasks` via this type instead of the today-sliced
/// `TaskListSnapshot.active` pool alone — that snapshot is list UX, not schedule truth.
public struct DayPlateInputs: Sendable, Equatable {
    /// Active non-template tasks from the full on-device pool.
    public var tasks: [LifeTask]
    /// Completions that belong on today's rail.
    public var completedToday: [LifeTask]
    /// Recurrence masters for projections / series resolution.
    public var recurrenceTemplates: [LifeTask]

    public init(
        tasks: [LifeTask],
        completedToday: [LifeTask],
        recurrenceTemplates: [LifeTask]
    ) {
        self.tasks = tasks
        self.completedToday = completedToday
        self.recurrenceTemplates = recurrenceTemplates
    }
}

public enum DayPlateBuilder {
    /// Splits the full task plate into pools for `LifeTimelinePresenter` / `TimelineService`.
    public static func inputs(
        from allTasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DayPlateInputs {
        let startOfDay = calendar.startOfDay(for: now)
        let templates = allTasks.filter(TaskRecurrenceEngine.isRecurrenceTemplate)
        let completedToday = allTasks.filter { task in
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            guard task.status == .completed else { return false }
            if let completedAt = task.completedAt {
                return completedAt >= startOfDay
            }
            // updatedAt defaults to now, so it cannot place a clock from another day on today's rail.
            if let scheduled = task.scheduledDate ?? task.scheduledTime,
               !calendar.isDate(scheduled, inSameDayAs: startOfDay) {
                return false
            }
            return task.updatedAt >= startOfDay
        }
        let tasks = allTasks.filter { task in
            !TaskRecurrenceEngine.isRecurrenceTemplate(task) && task.status.isActive
        }
        return DayPlateInputs(
            tasks: tasks,
            completedToday: completedToday,
            recurrenceTemplates: templates
        )
    }

    /// Full timeline events for an arbitrary day (draft plan / strip day).
    public static func events(
        from allTasks: [LifeTask],
        calendarEvents: [BriefingCalendarEvent] = [],
        bills: [BillItem] = [],
        shoppingItems: [ShoppingItem] = [],
        contacts: [RelationshipContact] = [],
        medications: [Medication] = [],
        now: Date = Date(),
        referenceDay: Date,
        calendar: Calendar = .current
    ) -> [LifeTimelineEvent] {
        let plate = inputs(from: allTasks, now: now, calendar: calendar)
        let isToday = calendar.isDate(referenceDay, inSameDayAs: now)
        return LifeTimelinePresenter.build(
            tasks: plate.tasks,
            completedToday: isToday ? plate.completedToday : [],
            recurrenceTemplates: plate.recurrenceTemplates,
            bills: bills,
            shoppingItems: shoppingItems,
            contacts: contacts,
            calendarEvents: calendarEvents,
            medications: isToday ? medications : [],
            now: now,
            referenceDay: referenceDay,
            calendar: calendar
        )
    }

    /// Active task rows that paint on today's schedule (for parked-restore gating).
    public static func scheduledTaskCount(
        from allTasks: [LifeTask],
        day: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let plate = inputs(from: allTasks, now: day, calendar: calendar)
        return TaskScheduleQuery.tasksForDay(
            from: plate.tasks,
            allTasks: plate.tasks + plate.completedToday + plate.recurrenceTemplates,
            day: day,
            calendar: calendar
        ).count
    }
}
