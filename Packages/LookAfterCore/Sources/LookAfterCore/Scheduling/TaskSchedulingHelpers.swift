import Foundation

/// Whether the scheduler may move a task automatically.
public enum TaskSchedulingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case flexible = "Flexible"
    case fixedTime = "Fixed Time"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .flexible:
            return "AI can reorder and reschedule this task."
        case .fixedTime:
            return "Locked start/end — office, gym, meetings, classes."
        }
    }
}

public extension LifeTask {

    var schedulingModeValue: TaskSchedulingMode {
        schedulingMode ?? .flexible
    }

    /// Resolved semantic time lock (defaults from schedulingMode when unset).
    var timeConstraintValue: TimeConstraint {
        timeConstraint ?? TimeConstraint.from(schedulingMode: schedulingMode)
    }

    var isFixedTimeEvent: Bool {
        timeConstraintValue == .anchored && scheduledTime != nil
            || (schedulingModeValue == .fixedTime && scheduledTime != nil && timeConstraint == nil)
    }

    /// Task materialized from compiled LifeModel commitments (gym, music, etc.).
    var isLifeCommitmentTask: Bool {
        tags.contains(LifeModel.commitmentTaskTag)
    }

    /// Life commitments and anchored blocks should not be moved by the day scheduler.
    var isSchedulerMovable: Bool {
        timeConstraintValue.isSchedulerMovable && !isLifeCommitmentTask && !isFixedTimeEvent
    }

    /// Apply a user-driven constraint mutation and keep schedulingMode aligned.
    mutating func applyTimeConstraint(_ constraint: TimeConstraint) {
        timeConstraint = constraint
        schedulingMode = constraint.asSchedulingMode
        updatedAt = Date()
    }

    /// Sync semantic constraint + clock fields after Flexible/Fixed picker edits.
    mutating func applyUserSchedulingModeEdit(
        _ mode: TaskSchedulingMode,
        fixedStartTime: Date? = nil,
        fixedEndTime: Date? = nil
    ) {
        switch mode {
        case .fixedTime:
            applyTimeConstraint(.anchored)
            scheduledTime = fixedStartTime
            scheduledEndTime = fixedEndTime
        case .flexible:
            applyTimeConstraint(.flexible)
            scheduledTime = nil
            scheduledEndTime = nil
        }
    }

    /// Effective compress floor for the conflict cascade.
    /// Explicit property > vault-learned floor > semantic defaults.
    func minimumViableDurationValue(
        vaultFloorMinutes: Int? = nil
    ) -> Int {
        if let minimumViableDuration {
            return max(TaskDurationPolicy.minimumMinutes, min(minimumViableDuration, estimatedMinutes))
        }
        if let vaultFloorMinutes {
            // Learned personal floor — still never above full duration.
            return max(TaskDurationPolicy.minimumMinutes, min(vaultFloorMinutes, estimatedMinutes))
        }
        let inferred: Int
        switch semanticProfile?.semanticType {
        case .deepWork, .learning, .creative:
            inferred = min(estimatedMinutes, max(45, estimatedMinutes * 2 / 3))
        case .physicalActivity:
            inferred = min(estimatedMinutes, max(30, estimatedMinutes * 2 / 3))
        case .selfCare, .medication:
            inferred = estimatedMinutes // never compress care/meds
        case .communication:
            inferred = min(estimatedMinutes, max(20, estimatedMinutes * 3 / 4))
        case .errand, .administrative, .generic, .none:
            inferred = min(estimatedMinutes, max(15, estimatedMinutes / 2))
        }
        return max(TaskDurationPolicy.minimumMinutes, inferred)
    }

    /// Convenience — static semantic floor without vault.
    var minimumViableDurationValue: Int {
        minimumViableDurationValue(vaultFloorMinutes: nil)
    }

    /// Calendar weekday integers (1 = Sunday … 7 = Saturday).
    var recurrenceWeekdaysValue: [Int] {
        recurrenceWeekdays ?? []
    }

    func recurrenceOccurs(on date: Date, calendar: Calendar = .current) -> Bool {
        // Templates keep a clock as time-of-day, so their series still starts at createdAt.
        // A non-template clock is a day assignment even when scheduledDate was never written.
        let anchor: Date
        if isRecurrenceTemplateTask {
            anchor = createdAt
        } else if let scheduledDate {
            anchor = scheduledDate
        } else if let scheduledTime {
            anchor = scheduledTime
        } else {
            anchor = createdAt
        }
        return recurrenceRule.occurs(
            on: date,
            anchoredOn: anchor,
            interval: recurrenceIntervalValue,
            weekdays: recurrenceWeekdays,
            calendar: calendar
        )
    }

    /// Whether this task should appear in today's execution list.
    func isActionableToday(
        allTasks: [LifeTask] = [],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        let context = allTasks.isEmpty ? [self] : allTasks
        return TaskRecurrenceEngine.isActionableToday(
            self,
            in: context,
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    /// Whether this active task belongs on a day's schedule/snapshot.
    /// Dated and time-only tasks stay on their scheduled day; deadline-only
    /// due tasks belong on that due day; overdue one-off carry-forwards land
    /// on `now`'s day. Unscheduled backlog stays off.
    func belongsOnDaySchedule(
        day: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        guard status.isActive else { return false }
        let dayStart = calendar.startOfDay(for: day)
        if isOverdueOneOffCarryForward(calendar: calendar, referenceDate: now) {
            return calendar.isDate(dayStart, inSameDayAs: now)
        }
        if isDeadlineOnlyDue(on: dayStart, calendar: calendar) {
            return true
        }
        if let scheduledDate {
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }
        if let scheduledTime {
            return calendar.isDate(scheduledTime, inSameDayAs: dayStart)
        }
        return false
    }

    /// Whether this task should appear on tomorrow's execution list.
    func isActionableTomorrow(
        allTasks: [LifeTask] = [],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        let context = allTasks.isEmpty ? [self] : allTasks
        return TaskRecurrenceEngine.isActionableTomorrow(
            self,
            in: context,
            calendar: calendar,
            referenceDate: referenceDate
        )
    }

    /// Scheduled on a future calendar day (after tomorrow).
    func isUpcoming(
        allTasks: [LifeTask] = [],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        guard status.isActive, !isRecurrenceTemplateTask else { return false }
        let context = allTasks.isEmpty ? [self] : allTasks
        if isActionableTomorrow(allTasks: context, calendar: calendar, referenceDate: referenceDate) {
            return false
        }
        guard let dayAfterTomorrow = calendar.date(
            byAdding: .day,
            value: 2,
            to: calendar.startOfDay(for: referenceDate)
        ) else {
            return false
        }
        if let scheduledDate {
            return scheduledDate >= dayAfterTomorrow
        }
        if let scheduledTime {
            return calendar.startOfDay(for: scheduledTime) >= dayAfterTomorrow
        }
        guard isDeadlineOnlyOneOff, let deadline else { return false }
        return calendar.startOfDay(for: deadline) >= dayAfterTomorrow
    }

    /// Active backlog without a scheduled day or deadline.
    /// Deadline-only one-offs belong on their due day, not inbox/someday.
    func isActiveBacklog(calendar: Calendar = .current, referenceDate: Date = Date()) -> Bool {
        status.isActive
            && !isRecurrenceTemplateTask
            && scheduledDate == nil
            && scheduledTime == nil
            && !isDeadlineOnlyOneOff
            && !isOverdue(calendar: calendar, referenceDate: referenceDate)
    }

    /// Has a time block assigned (today or future).
    func isScheduledTask(
        allTasks: [LifeTask] = [],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        guard status.isActive, !isRecurrenceTemplateTask else { return false }
        guard let scheduledTime else { return false }
        let scheduleDay = scheduledDate ?? calendar.startOfDay(for: scheduledTime)
        guard !isActionableToday(allTasks: allTasks, calendar: calendar, referenceDate: referenceDate) else {
            return false
        }
        // Tomorrow has its own bucket. A time-only clock due tomorrow is "this week",
        // not the residual scheduled-task list.
        guard !isActionableTomorrow(allTasks: allTasks, calendar: calendar, referenceDate: referenceDate) else {
            return false
        }
        guard !isUpcoming(allTasks: allTasks, calendar: calendar, referenceDate: referenceDate) else {
            return false
        }
        let context = allTasks.isEmpty ? [self] : allTasks
        return TaskRecurrenceEngine.matchesRecurrenceSchedule(
            self,
            on: scheduleDay,
            in: context,
            calendar: calendar
        )
    }

    /// "Active" tab — multi-day tasks, tasks actionable today, or recurring tasks/templates.
    /// Excludes tasks that have permanently ended (completed/skipped/expired/superseded).
    func isActiveTask(
        allTasks: [LifeTask] = [],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        guard status.isActive else { return false }
        if MultiDayTaskTags.isMultiDay(self) { return true }
        if isRecurrenceTemplateTask || isRecurring { return true }
        let context = allTasks.isEmpty ? [self] : allTasks
        return isActionableToday(allTasks: context, calendar: calendar, referenceDate: referenceDate)
    }

    /// "Scheduled" tab — fixed-time (not flexible) tasks with a concrete date+time falling this week.
    func isScheduledThisWeek(calendar: Calendar = .current, referenceDate: Date = Date()) -> Bool {
        guard status.isActive, !isRecurrenceTemplateTask else { return false }
        guard let scheduledTime else { return false }
        let scheduleDay = scheduledDate ?? scheduledTime
        guard schedulingModeValue == .fixedTime else { return false }
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return false }
        return weekInterval.contains(scheduleDay)
    }

    /// "Completed" tab — inactive (permanently ended) tasks with no future recurrence occurrence.
    func isInactiveWithNoFutureOccurrence(
        allTasks: [LifeTask] = [],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        guard !status.isActive, !isRecurrenceTemplateTask else { return false }
        let context = allTasks.isEmpty ? [self] : allTasks
        let template = TaskRecurrenceEngine.template(for: self, in: context)
        guard template.recurrenceRule != .none else { return true }
        let next = template.recurrenceRule.nextOccurrence(
            after: referenceDate,
            anchoredOn: template.createdAt,
            interval: template.recurrenceIntervalValue,
            weekdays: template.recurrenceWeekdays,
            calendar: calendar
        )
        return next == nil
    }

    /// Whether `now` falls inside this task's fixed window on the same calendar day.
    /// A clock from another day must not be remapped onto `now` — missing `scheduledDate`
    /// still carries a day in `scheduledTime`.
    func isActiveFixedTimeWindow(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isFixedTimeEvent, let start = scheduledTime else { return false }
        let clockDay = scheduledDate ?? start
        guard calendar.isDate(clockDay, inSameDayAs: now) else { return false }
        let day = calendar.startOfDay(for: now)
        guard let windowStart = calendar.combine(date: day, timeFrom: start) else { return false }
        let windowEnd: Date
        if let end = scheduledEndTime, let combinedEnd = calendar.combine(date: day, timeFrom: end) {
            windowEnd = combinedEnd > windowStart ? combinedEnd : combinedEnd.addingTimeInterval(24 * 3600)
        } else {
            windowEnd = windowStart.addingTimeInterval(TimeInterval(max(estimatedMinutes, 15) * 60))
        }
        return now >= windowStart && now <= windowEnd
    }

    /// Returns true when another task's fixed window overlaps this one's on the same day.
    func fixedWindowOverlaps(_ other: LifeTask, on day: Date, calendar: Calendar = .current) -> Bool {
        guard isFixedTimeEvent, other.isFixedTimeEvent,
              let startA = scheduledTime, let startB = other.scheduledTime else { return false }
        let dayStart = calendar.startOfDay(for: day)
        // A missing scheduledDate still carries a day in the clock — don't collide it onto another day.
        guard calendar.isDate(scheduledDate ?? startA, inSameDayAs: dayStart),
              calendar.isDate(other.scheduledDate ?? startB, inSameDayAs: dayStart) else {
            return false
        }

        guard let aStart = calendar.combine(date: dayStart, timeFrom: startA),
              let bStart = calendar.combine(date: dayStart, timeFrom: startB) else { return false }

        let aEnd = endTime(on: dayStart, calendar: calendar, defaultStart: aStart)
        let bEnd = other.endTime(on: dayStart, calendar: calendar, defaultStart: bStart)
        return aStart < bEnd && bStart < aEnd
    }

    fileprivate func endTime(on day: Date, calendar: Calendar, defaultStart: Date) -> Date {
        if let end = scheduledEndTime, let combined = calendar.combine(date: day, timeFrom: end) {
            return combined > defaultStart ? combined : combined.addingTimeInterval(24 * 3600)
        }
        return defaultStart.addingTimeInterval(TimeInterval(max(estimatedMinutes, 15) * 60))
    }
}

public extension Calendar {
    /// Yesterday relative to an explicit clock, not the wall clock.
    func isDateInYesterday(_ date: Date, reference: Date) -> Bool {
        guard let yesterday = self.date(byAdding: .day, value: -1, to: startOfDay(for: reference)) else {
            return false
        }
        return isDate(date, inSameDayAs: yesterday)
    }

    func combine(date day: Date, timeFrom time: Date) -> Date? {
        let parts = dateComponents([.hour, .minute, .second], from: time)
        return self.date(
            bySettingHour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: parts.second ?? 0,
            of: startOfDay(for: day)
        )
    }
}

public enum WeekdaySelection {
    public static let allSymbols: [(weekday: Int, label: String)] = {
        let calendar = Calendar.current
        return (1...7).map { weekday in
            let index = weekday - 1
            let label = calendar.shortWeekdaySymbols[index]
            return (weekday, label)
        }
    }()
}
