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
            guard !isSeriesFulfilled(on: day, for: template, in: allTasks, calendar: calendar) else { continue }
            guard !TaskSeriesResolver.shouldSkipMaterialization(for: template, on: day, in: allTasks, calendar: calendar) else { continue }

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
            guard !isSeriesFulfilled(on: day, for: template, in: allTasks, calendar: calendar) else { continue }
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
              calendar.isDate(scheduledDate, inSameDayAs: dayStart) else {
            if task.scheduledDate == nil,
               let time = task.scheduledTime,
               calendar.isDate(time, inSameDayAs: dayStart) {
                return true
            }
            return false
        }
        return matchesRecurrenceSchedule(task, on: scheduledDate, in: allTasks, calendar: calendar)
    }

    /// Plan merging duplicate recurrence templates that share a normalized title.
    public struct RecurrenceTemplateDedupePlan: Sendable, Equatable {
        public var occurrenceUpdates: [LifeTask]
        public var templateIDsToDelete: [String]

        public init(occurrenceUpdates: [LifeTask] = [], templateIDsToDelete: [String] = []) {
            self.occurrenceUpdates = occurrenceUpdates
            self.templateIDsToDelete = templateIDsToDelete
        }
    }

    /// Groups recurrence templates by normalized title and re-parents occurrences onto a single keeper.
    public static func dedupeDuplicateRecurrenceTemplates(
        in allTasks: [LifeTask],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> RecurrenceTemplateDedupePlan {
        let dayStart = calendar.startOfDay(for: referenceDate)
        let templates = allTasks.filter(isRecurrenceTemplate)
        var grouped: [String: [LifeTask]] = [:]
        for template in templates {
            let key = OnboardingTaskSeeder.normalizedRoutineTitle(template.title)
            grouped[key, default: []].append(template)
        }

        var occurrenceUpdates: [LifeTask] = []
        var templateIDsToDelete: [String] = []

        for (_, group) in grouped where group.count > 1 {
            guard let keeper = preferredRecurrenceTemplate(in: group, on: dayStart, allTasks: allTasks, calendar: calendar) else {
                continue
            }
            for duplicate in group where duplicate.id != keeper.id {
                templateIDsToDelete.append(duplicate.id)
                for var occurrence in allTasks where occurrence.parentTaskId == duplicate.id {
                    occurrence.parentTaskId = keeper.id
                    occurrence.updatedAt = Date()
                    occurrenceUpdates.append(occurrence)
                }
            }
        }

        return RecurrenceTemplateDedupePlan(
            occurrenceUpdates: occurrenceUpdates,
            templateIDsToDelete: templateIDsToDelete
        )
    }

    /// Recurring rows that duplicate an active life-commitment task with the same title (Gym + Gym, etc.).
    public static func recurringDuplicateIDsOfLifeCommitments(
        in allTasks: [LifeTask],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [String] {
        let dayStart = calendar.startOfDay(for: referenceDate)
        var ids = Set<String>()

        let commitments = allTasks.filter { task in
            guard task.isLifeCommitmentTask else { return false }
            if task.status.isActive { return true }
            guard task.status == .completed else { return false }
            if let completedAt = task.completedAt, calendar.isDate(completedAt, inSameDayAs: dayStart) {
                return true
            }
            if let scheduled = task.scheduledDate, calendar.isDate(scheduled, inSameDayAs: dayStart) {
                return true
            }
            return false
        }
        for commitment in commitments {
            let key = OnboardingTaskSeeder.normalizedRoutineTitle(commitment.title)
            guard !key.isEmpty else { continue }

            for task in allTasks where task.id != commitment.id && task.status.isActive {
                guard OnboardingTaskSeeder.normalizedRoutineTitle(task.title) == key else { continue }
                let isRecurringRow = task.parentTaskId != nil || isRecurrenceTemplate(task) || task.recurrenceRule != .none
                guard isRecurringRow else { continue }

                if isRecurrenceTemplate(task) {
                    ids.insert(task.id)
                    ids.formUnion(allTasks.filter { $0.parentTaskId == task.id }.map(\.id))
                    continue
                }

                if let scheduled = task.scheduledDate, calendar.isDate(scheduled, inSameDayAs: dayStart) {
                    ids.insert(task.id)
                }
            }
        }

        return Array(ids)
    }

    /// Active stored tasks that duplicate a just-completed instance on the same day.
    public static func duplicateActiveSeriesIDs(
        afterCompleting completed: LifeTask,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> [String] {
        guard completed.status == .completed else { return [] }
        let reference = completed.completedAt ?? completed.scheduledDate ?? Date()
        let dayStart = calendar.startOfDay(for: reference)
        let completedKey = TaskScheduleQuery.seriesKey(for: completed)
        var ids = Set<String>()

        for task in allTasks where task.id != completed.id && task.status.isActive {
            guard TaskScheduleQuery.seriesKey(for: task) == completedKey else { continue }
            if let scheduled = task.scheduledDate,
               !calendar.isDate(scheduled, inSameDayAs: dayStart) {
                continue
            }
            ids.insert(task.id)
        }

        ids.formUnion(
            recurringDuplicateIDsOfLifeCommitments(
                in: allTasks,
                calendar: calendar,
                referenceDate: dayStart
            )
        )
        return Array(ids)
    }

    /// Normalized series keys already satisfied today (completed life commitments, etc.).
    public static func fulfilledSeriesKeys(
        on day: Date,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Set<String> {
        let dayStart = calendar.startOfDay(for: day)
        var keys = Set<String>()
        for task in allTasks where task.status == .completed {
            let onDay = task.completedAt.map { calendar.isDate($0, inSameDayAs: dayStart) } == true
                || task.scheduledDate.map { calendar.isDate($0, inSameDayAs: dayStart) } == true
            guard onDay else { continue }
            keys.insert(TaskScheduleQuery.seriesKey(for: task))
            keys.insert("recurring|\(OnboardingTaskSeeder.normalizedRoutineTitle(task.title))")
        }
        return keys
    }

    /// Whether a recurrence series is already satisfied on `day` (completed instance, life commitment, etc.).
    public static func isSeriesFulfilled(
        on day: Date,
        for template: LifeTask,
        in allTasks: [LifeTask],
        calendar: Calendar
    ) -> Bool {
        let fulfilled = fulfilledSeriesKeys(on: day, in: allTasks, calendar: calendar)
        let seriesKey = TaskScheduleQuery.seriesKey(for: template)
        if fulfilled.contains(seriesKey) { return true }
        let titleKey = "recurring|\(OnboardingTaskSeeder.normalizedRoutineTitle(template.title))"
        return fulfilled.contains(titleKey)
    }

    /// Finds an existing recurrence template with the same normalized title, if any.
    public static func existingRecurrenceTemplate(
        matching task: LifeTask,
        in allTasks: [LifeTask]
    ) -> LifeTask? {
        let key = OnboardingTaskSeeder.normalizedRoutineTitle(task.title)
        return allTasks.first { candidate in
            isRecurrenceTemplate(candidate)
                && OnboardingTaskSeeder.normalizedRoutineTitle(candidate.title) == key
        }
    }

    private static func preferredRecurrenceTemplate(
        in group: [LifeTask],
        on day: Date,
        allTasks: [LifeTask],
        calendar: Calendar
    ) -> LifeTask? {
        group.max { lhs, rhs in
            let left = templateKeeperScore(lhs, on: day, allTasks: allTasks, calendar: calendar)
            let right = templateKeeperScore(rhs, on: day, allTasks: allTasks, calendar: calendar)
            if left != right { return left < right }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func templateKeeperScore(
        _ template: LifeTask,
        on day: Date,
        allTasks: [LifeTask],
        calendar: Calendar
    ) -> Int {
        var score = 0
        let occurrences = allTasks.filter { $0.parentTaskId == template.id }
        if occurrences.contains(where: { occ in
            occ.status.isActive
                && occ.scheduledDate.map { calendar.isDate($0, inSameDayAs: day) } == true
        }) {
            score += 100
        }
        if template.tags.contains("daily-routine") { score += 20 }
        if template.isRecurrenceTemplate == true { score += 10 }
        score += min(occurrences.count, 50)
        return score
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

            if task.parentTaskId == nil,
               task.status.isActive,
               hasActionableRecurringOccurrence(matching: task, on: scheduledDate, in: allTasks, calendar: calendar) {
                ids.insert(task.id)
                continue
            }

            if !matchesRecurrenceSchedule(task, on: scheduledDate, in: allTasks, calendar: calendar) {
                ids.insert(task.id)
            }
        }

        return Array(ids)
    }

    /// Standalone row superseded when an actionable recurring occurrence shares the same title on that day.
    private static func hasActionableRecurringOccurrence(
        matching task: LifeTask,
        on day: Date,
        in allTasks: [LifeTask],
        calendar: Calendar
    ) -> Bool {
        let key = OnboardingTaskSeeder.normalizedRoutineTitle(task.title)
        let dayStart = calendar.startOfDay(for: day)
        return allTasks.contains { other in
            guard other.id != task.id else { return false }
            guard other.parentTaskId != nil else { return false }
            guard other.status.isActive || other.status == .completed else { return false }
            guard OnboardingTaskSeeder.normalizedRoutineTitle(other.title) == key else { return false }
            guard let scheduledDate = other.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }
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
        var result = TaskEphemeralityDefaults.applyTemplatePolicy(occurrence, from: template)
        ScheduleNormalization.normalizeFields(&result, calendar: calendar)
        if TaskScheduleInterval.hasNoClockTime(result),
           let anchor = RoutineScheduleAnchorResolver.resolve(for: result, on: day, calendar: calendar) {
            result.scheduledTime = anchor.start
            result.scheduledEndTime = anchor.end
        }
        result = TaskConstraintAlignment.align(result)
        return result
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
