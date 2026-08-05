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
        let anchor = isRecurrenceTemplateTask ? createdAt : (scheduledDate ?? createdAt)
        return recurrenceRule.occurs(
            on: date,
            anchoredOn: anchor,
            interval: recurrenceIntervalValue,
            weekdays: recurrenceWeekdays,
            calendar: calendar
        )
    }

    /// Whether this task should appear in today's execution list.
    func isActionableToday(allTasks: [LifeTask] = [], calendar: Calendar = .current) -> Bool {
        let context = allTasks.isEmpty ? [self] : allTasks
        return TaskRecurrenceEngine.isActionableToday(self, in: context, calendar: calendar)
    }

    /// Whether this task should appear on tomorrow's execution list.
    func isActionableTomorrow(allTasks: [LifeTask] = [], calendar: Calendar = .current) -> Bool {
        let context = allTasks.isEmpty ? [self] : allTasks
        return TaskRecurrenceEngine.isActionableTomorrow(self, in: context, calendar: calendar)
    }

    /// Scheduled on a future calendar day (after tomorrow).
    func isUpcoming(allTasks: [LifeTask] = [], calendar: Calendar = .current) -> Bool {
        guard status.isActive, !isRecurrenceTemplateTask, let scheduledDate else { return false }
        let context = allTasks.isEmpty ? [self] : allTasks
        if isActionableTomorrow(allTasks: context, calendar: calendar) { return false }
        guard let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date())) else {
            return false
        }
        return scheduledDate >= dayAfterTomorrow
    }

    /// Active backlog without a scheduled day.
    func isActiveBacklog(calendar: Calendar = .current) -> Bool {
        status.isActive && !isRecurrenceTemplateTask && scheduledDate == nil && !isOverdue
    }

    /// Has a time block assigned (today or future).
    func isScheduledTask(allTasks: [LifeTask] = [], calendar: Calendar = .current) -> Bool {
        guard status.isActive, !isRecurrenceTemplateTask else { return false }
        guard scheduledTime != nil, let scheduledDate else { return false }
        guard !isActionableToday(allTasks: allTasks, calendar: calendar) else { return false }
        guard !isUpcoming(calendar: calendar) else { return false }
        let context = allTasks.isEmpty ? [self] : allTasks
        return TaskRecurrenceEngine.matchesRecurrenceSchedule(
            self,
            on: scheduledDate,
            in: context,
            calendar: calendar
        )
    }

    /// Whether `now` falls inside this task's fixed window on the same calendar day.
    func isActiveFixedTimeWindow(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isFixedTimeEvent, let start = scheduledTime else { return false }
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
