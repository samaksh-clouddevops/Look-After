import Foundation

/// Rows for the You-tab routine rings. A declared routine counts even when today's
/// occurrence was never written into the today task list.
public enum DailyRoutineBoard {
    /// Display-only marker. The row is part of the routine, but it does not fall on `now`.
    public static let offTodayTag = "routine-off-today"

    public static func rows(
        active: [LifeTask],
        completedToday: [LifeTask],
        templates: [LifeTask],
        blocks: [RoutineBlock],
        commitments: [LifeCommitment] = [],
        timeBlocks: [ProtectedTimeBlock] = [],
        now: Date,
        calendar: Calendar
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: now)
        var merged: [String: LifeTask] = [:]

        for task in active where isRoutineOccurrence(task) && isOn(task, day: day, calendar: calendar) {
            merged[key(task.title)] = task
        }
        for task in completedToday where isRoutineOccurrence(task) {
            merged[key(task.title)] = task
        }
        for template in templates where isRoutineRecord(template) {
            let titleKey = key(template.title)
            guard merged[titleKey] == nil else { continue }
            merged[titleKey] = projected(
                id: "routine-template-\(template.id)",
                title: template.title,
                minutes: template.estimatedMinutes,
                clock: clock(from: template.scheduledTime, on: day, calendar: calendar),
                onToday: occurs(template, on: day, calendar: calendar),
                now: now
            )
        }
        for block in blocks {
            let titleKey = key(block.title)
            guard merged[titleKey] == nil else { continue }
            let onToday = block.days.includes(day, calendar: calendar)
            merged[titleKey] = projected(
                id: "routine-block-\(block.id)",
                title: block.title,
                minutes: block.durationMinutes,
                clock: calendar.date(bySettingHour: block.startHour, minute: block.startMinute, second: 0, of: day),
                onToday: onToday,
                now: now
            )
        }
        for commitment in commitments {
            let titleKey = key(commitment.title)
            guard merged[titleKey] == nil else { continue }
            let block = timeBlocks.first { $0.label.caseInsensitiveCompare(commitment.preferredBlockLabel ?? "") == .orderedSame }
            merged[titleKey] = projected(
                id: "routine-commitment-\(commitment.id)",
                title: commitment.title,
                minutes: commitment.defaultMinutes,
                clock: block.flatMap { calendar.date(bySettingHour: $0.startHour, minute: $0.startMinute, second: 0, of: day) },
                onToday: commitment.frequency.applies(on: day, calendar: calendar),
                now: now
            )
        }
        for block in timeBlocks {
            let titleKey = key(block.label)
            guard !titleKey.isEmpty, merged[titleKey] == nil else { continue }
            let minutes = max(block.endMinutesFromMidnight - block.startMinutesFromMidnight, TaskDurationPolicy.minimumMinutes)
            merged[titleKey] = projected(
                id: "routine-time-\(block.id)",
                title: block.label,
                minutes: minutes,
                clock: calendar.date(bySettingHour: block.startHour, minute: block.startMinute, second: 0, of: day),
                onToday: block.days.includes(day, calendar: calendar),
                now: now
            )
        }

        return merged.values.sorted { lhs, rhs in
            let leftOff = lhs.tags.contains(offTodayTag)
            let rightOff = rhs.tags.contains(offTodayTag)
            if leftOff != rightOff { return !leftOff }
            switch (lhs.scheduledTime, rhs.scheduledTime) {
            case let (left?, right?):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private static func isRoutineOccurrence(_ task: LifeTask) -> Bool {
        guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
        return isRoutineRecord(task)
    }

    private static func isRoutineRecord(_ task: LifeTask) -> Bool {
        if task.tags.contains("daily-routine") || task.tags.contains("routine") { return true }
        if task.tags.contains(where: { $0.hasPrefix("routine-block:") }) { return true }
        if task.tags.contains(LifeModel.commitmentTaskTag) { return true }
        if task.tags.contains("onboarding"), task.tags.contains("fixed") { return true }
        if let anchor = task.scheduleAnchorID, anchor.hasPrefix("routine") { return true }
        return OnboardingTaskSeeder.isKnownDailyRoutineTitle(task.title)
    }

    private static func isOn(_ task: LifeTask, day: Date, calendar: Calendar) -> Bool {
        guard let assigned = task.assignedDay(calendar: calendar) else { return false }
        return calendar.isDate(assigned, inSameDayAs: day)
    }

    private static func occurs(_ template: LifeTask, on day: Date, calendar: Calendar) -> Bool {
        let rule = template.recurrenceRule
        guard rule != .none else { return true }
        return rule.occurs(
            on: day,
            anchoredOn: template.createdAt,
            interval: template.recurrenceIntervalValue,
            weekdays: template.recurrenceWeekdays,
            calendar: calendar
        )
    }

    private static func clock(from source: Date?, on day: Date, calendar: Calendar) -> Date? {
        guard let source else { return nil }
        return calendar.date(
            bySettingHour: calendar.component(.hour, from: source),
            minute: calendar.component(.minute, from: source),
            second: 0,
            of: day
        )
    }

    private static func projected(
        id: String,
        title: String,
        minutes: Int,
        clock: Date?,
        onToday: Bool,
        now: Date
    ) -> LifeTask {
        var tags = ["daily-routine", "routine"]
        if !onToday { tags.append(offTodayTag) }
        return LifeTask(
            id: id,
            title: title,
            estimatedMinutes: minutes,
            scheduledTime: clock,
            tags: tags,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
