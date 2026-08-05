import Foundation

/// Builds daily occurrences from recurrence templates — templates stay unchanged.
public enum TaskRecurrenceEngine {

    public static func template(for task: LifeTask, in tasks: [LifeTask]) -> LifeTask {
        if let parentId = task.parentTaskId,
           let parent = tasks.first(where: { $0.id == parentId }) {
            return parent
        }
        return task
    }

    public static func isRecurrenceTemplate(_ task: LifeTask) -> Bool {
        if task.isRecurrenceTemplate == true { return true }
        // Recurring master: has a rule but no day assignment and is not an occurrence.
        return task.recurrenceRule != .none
            && task.parentTaskId == nil
            && task.scheduledDate == nil
    }

    public static func needsLegacyNormalization(_ task: LifeTask) -> Bool {
        // Legacy format stored recurrence on the same record as a specific day instance.
        task.recurrenceRule != .none
            && task.parentTaskId == nil
            && task.isRecurrenceTemplate != true
            && task.scheduledDate != nil
    }

    /// Converts a legacy recurring root task into a template + linked occurrence.
    public static func normalizeLegacyRecurringTask(_ task: LifeTask) -> (template: LifeTask, occurrence: LifeTask) {
        var template = task
        template.isRecurrenceTemplate = true
        template.id = UUID().uuidString
        template.scheduledDate = nil
        template.status = .pending
        template.completedAt = nil

        var occurrence = task
        occurrence.parentTaskId = template.id
        occurrence.recurrence = nil
        occurrence.recurrenceInterval = nil
        occurrence.recurrenceWeekdays = nil
        occurrence.isRecurrenceTemplate = nil

        return (template, occurrence)
    }

    /// Occurrences that should exist on `date` but are not yet stored.
    public static func missingOccurrences(
        for allTasks: [LifeTask],
        on date: Date,
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: date)
        let templates = allTasks.filter(isRecurrenceTemplate)
        var results: [LifeTask] = []

        for template in templates {
            guard template.recurrenceOccurs(on: day, calendar: calendar) else { continue }
            guard !hasOccurrence(for: template, on: day, in: allTasks, calendar: calendar) else { continue }

            results.append(makeOccurrence(from: template, template: template, scheduledDate: day, calendar: calendar))
        }

        return results
    }

    public static func hasOccurrence(
        for template: LifeTask,
        on date: Date,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Bool {
        allTasks.contains { task in
            guard task.templateTaskId == template.id else { return false }
            guard let scheduledDate = task.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: date)
        }
    }

    /// Whether a stored task instance should count as due on `date` per its recurrence rule.
    public static func matchesRecurrenceSchedule(
        _ task: LifeTask,
        on date: Date,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Bool {
        if isRecurrenceTemplate(task) { return false }

        if let parentId = task.parentTaskId,
           !allTasks.contains(where: { $0.id == parentId }) {
            return false
        }

        // Same-title template fallback is for *legacy* duplicates only.
        // If this row already carries an explicit recurrence rule/weekdays that
        // differ from the template, prefer the occurrence (user override).
        if let seriesTemplate = duplicateSeriesTemplate(for: task, in: allTasks),
           !hasExplicitRecurrenceOverride(task, relativeTo: seriesTemplate) {
            return matchesRecurrenceSchedule(
                using: seriesTemplate,
                for: task,
                on: date,
                in: allTasks,
                calendar: calendar
            )
        }

        let source = recurrenceSource(for: task, in: allTasks)
        if source.recurrenceRule == .none {
            if task.parentTaskId != nil { return false }
            return true
        }

        return matchesRecurrenceSchedule(
            using: source,
            for: task,
            on: date,
            in: allTasks,
            calendar: calendar
        )
    }

    private static func matchesRecurrenceSchedule(
        using source: LifeTask,
        for task: LifeTask,
        on date: Date,
        in allTasks: [LifeTask],
        calendar: Calendar
    ) -> Bool {
        let anchor = recurrenceAnchor(for: task, source: source, in: allTasks, calendar: calendar)
        return source.recurrenceRule.occurs(
            on: date,
            anchoredOn: anchor,
            interval: source.recurrenceIntervalValue,
            weekdays: source.recurrenceWeekdays,
            calendar: calendar
        )
    }

    /// Legacy or duplicate rows that share a title with an existing recurrence template.
    private static func duplicateSeriesTemplate(for task: LifeTask, in allTasks: [LifeTask]) -> LifeTask? {
        guard task.parentTaskId == nil else { return nil }
        guard task.scheduledDate != nil else { return nil }
        guard needsLegacyNormalization(task) || task.recurrenceRule != .none else { return nil }
        return allTasks.first { candidate in
            guard isRecurrenceTemplate(candidate) else { return false }
            guard candidate.id != task.id else { return false }
            return candidate.title.caseInsensitiveCompare(task.title) == .orderedSame
        }
    }

    /// True when the occurrence intentionally diverges from the template schedule.
    private static func hasExplicitRecurrenceOverride(_ task: LifeTask, relativeTo template: LifeTask) -> Bool {
        if task.recurrenceRule != .none, task.recurrenceRule != template.recurrenceRule {
            return true
        }
        let taskDays = Set(task.recurrenceWeekdays ?? [])
        let templateDays = Set(template.recurrenceWeekdays ?? [])
        if !taskDays.isEmpty, taskDays != templateDays {
            return true
        }
        if let taskInterval = task.recurrenceInterval,
           taskInterval != template.recurrenceIntervalValue {
            return true
        }
        return false
    }

    /// First day the recurrence series may start generating instances.
    public static func recurrenceAnchor(
        for task: LifeTask,
        source: LifeTask,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Date {
        if isRecurrenceTemplate(source) {
            return calendar.startOfDay(for: source.createdAt)
        }
        if let parentId = task.parentTaskId,
           let parent = allTasks.first(where: { $0.id == parentId }) {
            return calendar.startOfDay(for: parent.createdAt)
        }
        if let firstDay = source.scheduledDate {
            return calendar.startOfDay(for: firstDay)
        }
        return calendar.startOfDay(for: source.createdAt)
    }

    /// Task record that owns the recurrence rule — occurrence overrides beat the parent template.
    public static func recurrenceSource(for task: LifeTask, in allTasks: [LifeTask]) -> LifeTask {
        if task.recurrenceRule != .none { return task }
        let template = template(for: task, in: allTasks)
        if template.recurrenceRule != .none { return template }
        if task.parentTaskId != nil { return template }
        return task
    }

    /// Whether this task belongs in today's execution list.
    public static func isActionableToday(
        _ task: LifeTask,
        in allTasks: [LifeTask],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        isActionable(on: calendar.startOfDay(for: referenceDate), task: task, in: allTasks, calendar: calendar)
    }

    /// Whether this task belongs on tomorrow's execution list.
    public static func isActionableTomorrow(
        _ task: LifeTask,
        in allTasks: [LifeTask],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate)) else {
            return false
        }
        return isActionable(on: tomorrow, task: task, in: allTasks, calendar: calendar)
    }

    /// Whether this task belongs on a specific calendar day's execution list.
    public static func isActionable(
        on day: Date,
        task: LifeTask,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Bool {
        isActionableOnDayStart(calendar.startOfDay(for: day), task: task, in: allTasks, calendar: calendar)
    }

    private static func isActionableOnDayStart(
        _ dayStart: Date,
        task: LifeTask,
        in allTasks: [LifeTask],
        calendar: Calendar
    ) -> Bool {
        guard task.status.isActive, !isRecurrenceTemplate(task) else { return false }
        if task.isOverdue {
            guard let scheduledDate = task.scheduledDate else { return calendar.isDateInToday(dayStart) }
            guard calendar.isDate(scheduledDate, inSameDayAs: dayStart) else { return false }
            return matchesRecurrenceSchedule(task, on: scheduledDate, in: allTasks, calendar: calendar)
        }
        guard let scheduledDate = task.scheduledDate,
              calendar.isDate(scheduledDate, inSameDayAs: dayStart) else { return false }
        return matchesRecurrenceSchedule(task, on: scheduledDate, in: allTasks, calendar: calendar)
    }

    /// Occurrence ids whose scheduled day does not match the parent recurrence rule.
    public static func invalidOccurrenceIDs(
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> [String] {
        invalidScheduledTaskIDs(in: allTasks, calendar: calendar)
    }

    /// Active or legacy task ids scheduled on a day that violates their recurrence rule.
    public static func invalidScheduledTaskIDs(
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> [String] {
        var ids = Set<String>()

        for task in allTasks {
            guard !isRecurrenceTemplate(task) else { continue }
            guard let scheduledDate = task.scheduledDate else { continue }

            if task.parentTaskId != nil,
               !allTasks.contains(where: { $0.id == task.parentTaskId }) {
                ids.insert(task.id)
                continue
            }

            if duplicateSeriesTemplate(for: task, in: allTasks) != nil {
                ids.insert(task.id)
                continue
            }

            if !matchesRecurrenceSchedule(task, on: scheduledDate, in: allTasks, calendar: calendar) {
                ids.insert(task.id)
            }
        }

        return Array(ids)
    }

    public static func nextScheduledDate(
        for completedTask: LifeTask,
        template: LifeTask,
        calendar: Calendar = .current
    ) -> Date? {
        guard completedTask.recurrenceRule != .none || template.recurrenceRule != .none else {
            return nil
        }

        let rule = template.recurrenceRule != .none ? template.recurrenceRule : completedTask.recurrenceRule
        let anchor = template.createdAt
        let interval = template.recurrenceIntervalValue
        let weekdays = template.recurrenceWeekdays
        let after = completedTask.completedAt ?? Date()

        return rule.nextOccurrence(
            after: after,
            anchoredOn: anchor,
            interval: interval,
            weekdays: weekdays,
            calendar: calendar
        )
    }

    public static func makeOccurrence(
        from source: LifeTask,
        template: LifeTask,
        scheduledDate: Date,
        calendar: Calendar = .current
    ) -> LifeTask {
        let day = calendar.startOfDay(for: scheduledDate)
        return LifeTask(
            title: template.title,
            description: template.description,
            lifeArea: template.lifeArea,
            priority: template.priority,
            difficulty: template.difficulty,
            status: .pending,
            steps: template.steps.map {
                TaskStep(title: $0.title, estimatedMinutes: $0.estimatedMinutes)
            },
            estimatedMinutes: template.estimatedMinutes,
            requiredEnergy: template.requiredEnergy,
            deadline: template.deadline,
            scheduledDate: day,
            scheduledTime: scheduledTime(on: day, from: template, calendar: calendar),
            tags: template.tags,
            notes: template.notes,
            parentTaskId: template.id,
            schedulingMode: template.schedulingMode,
            scheduledEndTime: scheduledEndTime(on: day, from: template, calendar: calendar),
            userId: source.userId,
            semanticProfile: template.semanticProfile
        )
    }

    public static func makeNextOccurrence(
        from completedTask: LifeTask,
        template: LifeTask,
        scheduledDate: Date,
        calendar: Calendar = .current
    ) -> LifeTask {
        makeOccurrence(from: completedTask, template: template, scheduledDate: scheduledDate, calendar: calendar)
    }

    public static func scheduledTime(on day: Date, from template: LifeTask, calendar: Calendar = .current) -> Date? {
        guard let source = template.scheduledTime else { return nil }
        return calendar.combine(date: day, timeFrom: source)
    }

    public static func scheduledEndTime(on day: Date, from template: LifeTask, calendar: Calendar = .current) -> Date? {
        guard let source = template.scheduledEndTime else { return nil }
        return calendar.combine(date: day, timeFrom: source)
    }
}
