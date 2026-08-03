import Foundation

/// Human-facing timeline event kinds — life activities, not task-manager categories.
public enum LifeTimelineEventKind: String, Sendable, CaseIterable {
    case work
    case meeting
    case health
    case medication
    case travel
    case shopping
    case habit
    case exercise
    case recovery
    case personal
    case creative
    case finance
    case bill
    case relationship

    public var emoji: String {
        switch self {
        case .work: return "💼"
        case .meeting: return "📅"
        case .health: return "❤️"
        case .medication: return "💊"
        case .travel: return "✈️"
        case .shopping: return "🛒"
        case .habit: return "🔁"
        case .exercise: return "🏃"
        case .recovery: return "🧘"
        case .personal: return "🌿"
        case .creative: return "🎵"
        case .finance: return "💰"
        case .bill: return "🧾"
        case .relationship: return "👥"
        }
    }

    public var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .meeting: return "calendar"
        case .health: return "heart.fill"
        case .medication: return "pills.fill"
        case .travel: return "airplane"
        case .shopping: return "cart.fill"
        case .habit: return "repeat.circle.fill"
        case .exercise: return "figure.run"
        case .recovery: return "leaf.fill"
        case .personal: return "person.fill"
        case .creative: return "music.note"
        case .finance: return "dollarsign.circle.fill"
        case .bill: return "creditcard.fill"
        case .relationship: return "person.2.fill"
        }
    }

    public var sectionLabel: String {
        switch self {
        case .work: return "Work"
        case .meeting: return "Meeting"
        case .health: return "Health"
        case .medication: return "Medication"
        case .travel: return "Travel"
        case .shopping: return "Shopping"
        case .habit: return "Habit"
        case .exercise: return "Exercise"
        case .recovery: return "Recovery"
        case .personal: return "Personal"
        case .creative: return "Creative"
        case .finance: return "Finance"
        case .bill: return "Bill"
        case .relationship: return "Relationship"
        }
    }
}

/// A grouped, human-facing timeline event — never exposes internal planning blocks.
public struct LifeTimelineEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: LifeTimelineEventKind
    public let title: String
    public let subtitle: String
    public let detailLines: [String]
    public let date: Date
    public let estimatedMinutes: Int?
    public let isCompleted: Bool
    public let isFixed: Bool
    public let completedAt: Date?

    public init(
        id: String,
        kind: LifeTimelineEventKind,
        title: String,
        subtitle: String = "",
        detailLines: [String] = [],
        date: Date,
        estimatedMinutes: Int? = nil,
        isCompleted: Bool = false,
        isFixed: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.detailLines = detailLines
        self.date = date
        self.estimatedMinutes = estimatedMinutes
        self.isCompleted = isCompleted
        self.isFixed = isFixed
        self.completedAt = completedAt
    }
}

/// Builds a life-oriented timeline — groups shopping/finance, formats medications, hides block jargon.
public enum LifeTimelinePresenter {
    public static func build(
        tasks: [LifeTask],
        completedToday: [LifeTask],
        recurrenceTemplates: [LifeTask] = [],
        bills: [BillItem],
        shoppingItems: [ShoppingItem],
        contacts: [RelationshipContact],
        calendarEvents: [BriefingCalendarEvent] = [],
        medications: [Medication] = [],
        now: Date = Date(),
        referenceDay: Date? = nil,
        calendar: Calendar = .current
    ) -> [LifeTimelineEvent] {
        let dayAnchor = referenceDay.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)
        let isToday = calendar.isDate(dayAnchor, inSameDayAs: now)
        var events: [LifeTimelineEvent] = []
        let allTasks = tasks + completedToday + recurrenceTemplates
        let timelineTasks = tasksForDayTimeline(
            from: tasks,
            allTasks: allTasks,
            day: dayAnchor,
            referenceNow: now,
            calendar: calendar
        )
        let timelineCompleted = isToday
            ? completedTasksForTodayTimeline(
                from: completedToday,
                allTasks: allTasks,
                now: now,
                calendar: calendar
            )
            : []
        var eventTaskIds = Set<String>()

        let activeTasks = timelineTasks.filter { $0.status.isActive && !isShoppingErrandTask($0) }
        let financeTasks = activeTasks.filter { isFinanceTask($0) }
        let nonFinanceTasks = activeTasks.filter { !isFinanceTask($0) && !isShoppingErrandTask($0) }

        for task in nonFinanceTasks {
            guard !OnboardingTaskSeeder.isJunkOnboardingTask(title: task.title, description: task.description) else { continue }
            guard let event = taskEvent(from: task, allTasks: allTasks, now: now) else { continue }
            events.append(event)
            eventTaskIds.insert(task.id)
        }

        if !financeTasks.isEmpty {
            events.append(groupedFinanceSession(tasks: financeTasks, now: now, calendar: calendar))
        }

        let unpurchased = shoppingItems.filter { !$0.isPurchased }
        if isToday, !unpurchased.isEmpty {
            let shoppingTask = tasks.first(where: isShoppingErrandTask)
            events.append(groupedShoppingTrip(items: unpurchased, scheduledTask: shoppingTask, now: now, calendar: calendar))
        }

        if isToday {
            for med in medications where calendar.isDateInToday(med.scheduledTime) || med.isTaken {
                events.append(medicationEvent(from: med, calendar: calendar))
            }
        }

        for bill in bills where !bill.isPaid {
            guard calendar.isDate(bill.dueDate, inSameDayAs: dayAnchor) else { continue }
            events.append(LifeTimelineEvent(
                id: "bill-\(bill.id)",
                kind: .bill,
                title: humanBillTitle(bill.title),
                subtitle: bill.isOverdue ? "Overdue" : "Due today",
                date: bill.dueDate
            ))
        }

        for contact in contacts {
            guard let birthday = contact.birthday else { continue }
            let next = nextBirthday(from: birthday, now: dayAnchor, calendar: calendar)
            guard calendar.isDate(next, inSameDayAs: dayAnchor) else { continue }
            events.append(LifeTimelineEvent(
                id: "bday-\(contact.id)",
                kind: .relationship,
                title: "\(contact.name)'s birthday",
                subtitle: "Reach out today",
                date: next
            ))
        }

        for event in calendarEvents where calendar.isDate(event.startDate, inSameDayAs: dayAnchor) {
            events.append(LifeTimelineEvent(
                id: "cal-\(event.id)",
                kind: .meeting,
                title: UserFacingCopy.sanitize(event.title).isEmpty ? event.title : UserFacingCopy.sanitize(event.title),
                subtitle: event.timeLabel,
                date: event.startDate,
                isFixed: true
            ))
        }

        for task in timelineCompleted {
            guard !eventTaskIds.contains(task.id) else { continue }
            guard let event = taskEvent(from: task, allTasks: allTasks, now: now, forceCompleted: true) else { continue }
            events.append(event)
        }

        return events
            .filter { calendar.isDate($0.date, inSameDayAs: dayAnchor) || $0.date >= dayAnchor }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Task → event

    /// Tasks that belong on a specific day's timeline — respects recurrence rules and scheduled days.
    private static func tasksForDayTimeline(
        from tasks: [LifeTask],
        allTasks: [LifeTask],
        day: Date,
        referenceNow: Date,
        calendar: Calendar
    ) -> [LifeTask] {
        let isToday = calendar.isDate(day, inSameDayAs: referenceNow)
        return tasks.filter { task in
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            guard !MultiDayTaskTags.isRoot(task) else { return false }

            if task.scheduledDate != nil || task.scheduledTime != nil {
                return TaskRecurrenceEngine.isActionable(on: day, task: task, in: allTasks, calendar: calendar)
            }

            return isToday && (task.status.isActive || task.status == .completed) && task.recurrenceRule == .none
        }
    }

    /// Tasks that belong on today's timeline — respects recurrence rules and scheduled days.
    private static func tasksForTodayTimeline(
        from tasks: [LifeTask],
        allTasks: [LifeTask],
        now: Date,
        calendar: Calendar
    ) -> [LifeTask] {
        tasksForDayTimeline(
            from: tasks,
            allTasks: allTasks,
            day: calendar.startOfDay(for: now),
            referenceNow: now,
            calendar: calendar
        )
    }

    /// Completed tasks stay on today's timeline — greyed with a filled progress dot.
    private static func completedTasksForTodayTimeline(
        from completedToday: [LifeTask],
        allTasks: [LifeTask],
        now: Date,
        calendar: Calendar
    ) -> [LifeTask] {
        let startOfDay = calendar.startOfDay(for: now)
        return completedToday.filter { task in
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            guard task.status == .completed else { return false }
            guard let completedAt = task.completedAt, completedAt >= startOfDay else { return false }

            if task.scheduledDate != nil || task.scheduledTime != nil {
                if let scheduledDate = task.scheduledDate {
                    return calendar.isDate(scheduledDate, inSameDayAs: now)
                        || TaskRecurrenceEngine.matchesRecurrenceSchedule(
                            task,
                            on: scheduledDate,
                            in: allTasks,
                            calendar: calendar
                        )
                }
                if let scheduledTime = task.scheduledTime {
                    return calendar.isDate(scheduledTime, inSameDayAs: now)
                }
            }
            return true
        }
    }

    private static func taskEvent(from task: LifeTask, allTasks: [LifeTask], now: Date, forceCompleted: Bool = false) -> LifeTimelineEvent? {
        let title = timelineTitle(for: task)
        guard !title.isEmpty else { return nil }
        return makeTaskEvent(task: task, title: title, allTasks: allTasks, now: now, forceCompleted: forceCompleted)
    }

    private static func timelineTitle(for task: LifeTask) -> String {
        let sanitizedTitle = UserFacingCopy.sanitize(task.title)
        if !sanitizedTitle.isEmpty, !UserFacingCopy.isInternalExecutionLabel(sanitizedTitle) {
            return sanitizedTitle
        }

        let headline = HumanLanguage.outcomeHeadline(task: task)
        if !UserFacingCopy.isInternalExecutionLabel(headline),
           !OnboardingTaskSeeder.isJunkOnboardingTask(title: headline, description: task.description) {
            return headline
        }

        if let subtype = task.semanticProfile?.subtype, !subtype.isEmpty {
            return subtype
        }

        return ""
    }

    private static func makeTaskEvent(task: LifeTask, title: String, allTasks: [LifeTask], now: Date, forceCompleted: Bool) -> LifeTimelineEvent {
        let when = task.scheduledTime ?? task.scheduledDate ?? task.deadline ?? task.createdAt
        let kind = kindForTask(task)
        let duration = task.estimatedMinutes > 0 ? task.estimatedMinutes : nil
        let subtitle: String
        if forceCompleted || task.status == .completed {
            subtitle = "Done"
        } else if let duration {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            if let start = task.scheduledTime {
                let day = Calendar.current.startOfDay(for: when)
                let end = TaskScheduleInterval.endDate(for: task, on: day, calendar: .current) ?? start.addingTimeInterval(TimeInterval(duration * 60))
                subtitle = ScheduleTimeFormatting.rangeLabel(from: start, to: end)
            } else {
                subtitle = "About \(duration) min"
            }
        } else {
            subtitle = kind.sectionLabel
        }

        var displaySubtitle = subtitle
        if MultiDayTaskTags.isSlice(task),
           let parentId = task.parentTaskId,
           let parent = allTasks.first(where: { $0.id == parentId }) {
            displaySubtitle = "\(parent.title) · \(subtitle)"
        }

        return LifeTimelineEvent(
            id: "task-\(task.id)",
            kind: kind,
            title: title,
            subtitle: displaySubtitle,
            date: when,
            estimatedMinutes: duration,
            isCompleted: forceCompleted || task.status == .completed,
            isFixed: task.isFixedTimeEvent,
            completedAt: task.completedAt
        )
    }

    public static func kindForTask(_ task: LifeTask) -> LifeTimelineEventKind {
        let base = baseKindForTask(task)
        // Fixed work blocks (standup, meetings) use the calendar icon — not gym, meds, etc.
        if task.isFixedTimeEvent, base == .work {
            return .meeting
        }
        return base
    }

    private static func baseKindForTask(_ task: LifeTask) -> LifeTimelineEventKind {
        let lower = task.title.lowercased()
        if lower.contains("gym") || lower.contains("workout") || lower.contains("yoga") || lower.contains("run") {
            return .exercise
        }

        switch task.resolvedSemanticProfile.semanticType {
        case .medication: return .medication
        case .physicalActivity: return .exercise
        case .errand: return .shopping
        case .creative: return .creative
        case .communication: return .work
        case .selfCare: return .recovery
        case .learning: return .personal
        default: break
        }
        switch task.lifeArea {
        case .work: return .work
        case .health: return .health
        case .finance: return .finance
        case .shopping: return .shopping
        case .travel: return .travel
        case .medication: return .medication
        case .creativity: return .creative
        case .personal, .reflection: return .personal
        case .relationships: return .relationship
        case .home: return .personal
        case .learning: return .personal
        case .hydration: return .health
        }
    }

    // MARK: - Grouped shopping

    private static func groupedShoppingTrip(
        items: [ShoppingItem],
        scheduledTask: LifeTask?,
        now: Date,
        calendar: Calendar
    ) -> LifeTimelineEvent {
        let names = items.map(\.name).sorted()
        let when: Date
        if let task = scheduledTask, let time = task.scheduledTime {
            when = time
        } else if let task = scheduledTask, let date = task.scheduledDate {
            let workHours = PlanningSchedulePolicy.WorkHours.from(profile: UserLifeProfileStore.load())
            let slot = PlanningSchedulePolicy.nextAvailableSlot(workHours: workHours)
                ?? (workHours.startHour, 0)
            when = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: date) ?? date
        } else {
            let workHours = PlanningSchedulePolicy.WorkHours.from(profile: UserLifeProfileStore.load())
            when = PlanningSchedulePolicy.schedulingCursor(workHours: workHours)
        }
        let minutes = scheduledTask?.estimatedMinutes ?? min(45, 15 + names.count * 3)
        return LifeTimelineEvent(
            id: "shopping-trip",
            kind: .shopping,
            title: "Stop at the grocery store",
            subtitle: "About \(minutes) minutes",
            detailLines: names,
            date: when,
            estimatedMinutes: minutes
        )
    }

    // MARK: - Grouped finance

    private static func groupedFinanceSession(tasks: [LifeTask], now: Date, calendar: Calendar) -> LifeTimelineEvent {
        let lines = tasks.compactMap { task -> String? in
            let headline = HumanLanguage.outcomeHeadline(task: task)
            return UserFacingCopy.isInternalExecutionLabel(headline) ? task.title : headline
        }
        let earliest = tasks.compactMap { $0.scheduledTime ?? $0.scheduledDate }.min() ?? now
        let when = earliest < now
            ? (calendar.date(bySettingHour: calendar.component(.hour, from: now) + 1, minute: 0, second: 0, of: now) ?? now)
            : earliest
        let minutes = tasks.reduce(0) { $0 + max($1.estimatedMinutes, TaskDurationPolicy.minimumMinutes) }
        return LifeTimelineEvent(
            id: "finance-session",
            kind: .finance,
            title: "Finance session",
            subtitle: "About \(minutes) minutes",
            detailLines: lines,
            date: when,
            estimatedMinutes: minutes
        )
    }

    // MARK: - Medication

    private static func medicationEvent(from med: Medication, calendar: Calendar) -> LifeTimelineEvent {
        let hour = calendar.component(.hour, from: med.scheduledTime)
        let period: String
        switch hour {
        case ..<12: period = "Morning"
        case 12..<17: period = "Afternoon"
        default: period = "Evening"
        }
        let instruction = medicationInstruction(name: med.name, dosage: med.dosage)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeLabel = formatter.string(from: med.scheduledTime)

        return LifeTimelineEvent(
            id: "med-\(med.id)",
            kind: .medication,
            title: "\(period) medication",
            subtitle: med.isTaken ? "Taken · \(instruction)" : "\(timeLabel) · \(instruction)",
            date: med.isTaken ? (med.lastTakenAt ?? med.scheduledTime) : med.scheduledTime,
            isCompleted: med.isTaken,
            isFixed: true
        )
    }

    private static func medicationInstruction(name: String, dosage: String) -> String {
        let lower = name.lowercased()
        if lower.contains("levothyroxine") || lower.contains("thyroid") {
            return "Take \(name) on an empty stomach"
        }
        if dosage.isEmpty {
            return "Take \(name)"
        }
        return "Take \(name) · \(dosage)"
    }

    // MARK: - Helpers

    private static func isFinanceTask(_ task: LifeTask) -> Bool {
        task.lifeArea == .finance
            || (task.resolvedSemanticProfile.semanticType == .administrative && task.title.lowercased().contains("financ"))
    }

    private static func isShoppingErrandTask(_ task: LifeTask) -> Bool {
        task.lifeArea == .shopping
            || task.resolvedSemanticProfile.semanticType == .errand
            || task.title.lowercased().contains("grocery")
            || task.title.lowercased().contains("shopping")
    }

    private static func humanBillTitle(_ title: String) -> String {
        let cleaned = UserFacingCopy.sanitize(title)
        if cleaned.isEmpty { return "Pay \(title)" }
        if cleaned.lowercased().hasPrefix("pay ") { return cleaned }
        return "Pay \(cleaned)"
    }

    private static func nextBirthday(from birthday: Date, now: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.month, .day], from: birthday)
        components.year = calendar.component(.year, from: now)
        guard var candidate = calendar.date(from: components) else { return birthday }
        if candidate < calendar.startOfDay(for: now) {
            components.year = (components.year ?? 0) + 1
            candidate = calendar.date(from: components) ?? candidate
        }
        return candidate
    }
}
