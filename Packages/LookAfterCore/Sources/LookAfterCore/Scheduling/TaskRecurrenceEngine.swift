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
        let index = OccurrenceDayIndex.build(from: allTasks, calendar: calendar)
        var results: [LifeTask] = []

        for template in templates {
            guard template.recurrenceOccurs(on: day, calendar: calendar) else { continue }
            guard !hasStoredOccurrence(for: template, on: day, index: index, calendar: calendar) else { continue }

            results.append(makeOccurrence(from: template, template: template, scheduledDate: day, calendar: calendar))
        }

        return results
    }

    /// In-memory occurrences for timeline display when no live row exists yet.
    public static func timelineProjections(
        for allTasks: [LifeTask],
        on date: Date,
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: date)
        let templates = allTasks.filter(isRecurrenceTemplate)
        let index = OccurrenceDayIndex.build(from: allTasks, calendar: calendar)
        var results: [LifeTask] = []

        for template in templates {
            guard template.recurrenceOccurs(on: day, calendar: calendar) else { continue }
            guard !hasActionableOccurrence(for: template, on: day, index: index, calendar: calendar) else { continue }
            guard !template.isLifeCommitmentTask else { continue }
            results.append(timelineProjectionOccurrence(from: template, on: day, calendar: calendar))
        }

        return results
    }

    /// Stable id for in-memory timeline projections — matches across rebuilds until materialized.
    public static func stableProjectionID(
        templateId: String,
        on day: Date,
        calendar: Calendar = .current
    ) -> String {
        let dayStart = calendar.startOfDay(for: day)
        let components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        let y = components.year ?? 0
        let m = components.month ?? 0
        let d = components.day ?? 0
        return "proj-\(templateId)-\(y)\(String(format: "%02d", m))\(String(format: "%02d", d))"
    }

    /// In-memory occurrence for timeline display — id is stable until persisted.
    public static func timelineProjectionOccurrence(
        from template: LifeTask,
        on date: Date,
        calendar: Calendar = .current
    ) -> LifeTask {
        var occurrence = makeOccurrence(from: template, template: template, scheduledDate: date, calendar: calendar)
        occurrence.id = stableProjectionID(templateId: template.id, on: date, calendar: calendar)
        return occurrence
    }

    /// Any stored row for template+day — prevents duplicate DB materialization.
    public static func hasStoredOccurrence(
        for template: LifeTask,
        on date: Date,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Bool {
        let index = OccurrenceDayIndex.build(from: allTasks, calendar: calendar)
        return hasStoredOccurrence(for: template, on: date, index: index, calendar: calendar)
    }

    /// Active or completed row for template+day — drives timeline and task lists.
    public static func hasActionableOccurrence(
        for template: LifeTask,
        on date: Date,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Bool {
        let index = OccurrenceDayIndex.build(from: allTasks, calendar: calendar)
        return hasActionableOccurrence(for: template, on: date, index: index, calendar: calendar)
    }

    /// Backward-compatible alias — stored rows block sync duplication.
    public static func hasOccurrence(
        for template: LifeTask,
        on date: Date,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Bool {
        hasStoredOccurrence(for: template, on: date, in: allTasks, calendar: calendar)
    }

    private static func hasStoredOccurrence(
        for template: LifeTask,
        on date: Date,
        index: OccurrenceDayIndex,
        calendar: Calendar
    ) -> Bool {
        !index.tasks(for: template.id, on: date, calendar: calendar).isEmpty
    }

    private static func hasActionableOccurrence(
        for template: LifeTask,
        on date: Date,
        index: OccurrenceDayIndex,
        calendar: Calendar
    ) -> Bool {
        index.tasks(for: template.id, on: date, calendar: calendar).contains {
            $0.status.isActive || $0.status == .completed
        }
    }

    /// Fast lookup of occurrence rows by template id + scheduled day.
    private struct OccurrenceDayIndex {
        let byTemplateDay: [String: [LifeTask]]

        static func build(from allTasks: [LifeTask], calendar: Calendar) -> OccurrenceDayIndex {
            var map: [String: [LifeTask]] = [:]
            for task in allTasks {
                guard !isRecurrenceTemplate(task) else { continue }
                guard task.parentTaskId != nil else { continue }
                guard let scheduledDate = task.scheduledDate else { continue }
                let key = Self.key(templateId: task.templateTaskId, day: calendar.startOfDay(for: scheduledDate))
                map[key, default: []].append(task)
            }
            return OccurrenceDayIndex(byTemplateDay: map)
        }

        static func key(templateId: String, day: Date) -> String {
            "\(templateId)|\(Int(day.timeIntervalSince1970))"
        }

        func tasks(for templateId: String, on date: Date, calendar: Calendar) -> [LifeTask] {
            let day = calendar.startOfDay(for: date)
            return byTemplateDay[Self.key(templateId: templateId, day: day)] ?? []
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

        if duplicateSeriesTemplate(for: task, in: allTasks) != nil {
            return false
        }

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
        let occurrence = LifeTask(
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
        return TaskEphemeralityDefaults.applyTemplatePolicy(occurrence, from: template)
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
