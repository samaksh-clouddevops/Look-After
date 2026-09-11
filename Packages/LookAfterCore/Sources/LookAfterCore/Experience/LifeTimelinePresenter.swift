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
    /// Semantic time lock from the source task when available.
    public let timeConstraint: TimeConstraint?
    public let completedAt: Date?
    /// Task priority used to order flexible same-day events (higher first).
    public let sortPriority: Int
    public let scheduleKind: TimelineScheduleKind

    public var resolvedTimeConstraint: TimeConstraint {
        timeConstraint ?? (isFixed ? .anchored : .flexible)
    }

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
        timeConstraint: TimeConstraint? = nil,
        completedAt: Date? = nil,
        sortPriority: Int = 0,
        scheduleKind: TimelineScheduleKind = .fixedWindow
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
        self.timeConstraint = timeConstraint
        self.completedAt = completedAt
        self.sortPriority = sortPriority
        self.scheduleKind = scheduleKind
    }

    public func withCompletion(_ isCompleted: Bool, at completedAt: Date? = Date()) -> LifeTimelineEvent {
        LifeTimelineEvent(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            detailLines: detailLines,
            date: date,
            estimatedMinutes: estimatedMinutes,
            isCompleted: isCompleted,
            isFixed: isFixed,
            timeConstraint: timeConstraint,
            completedAt: isCompleted ? completedAt : nil,
            sortPriority: sortPriority,
            scheduleKind: scheduleKind
        )
    }

    public func withDate(_ date: Date) -> LifeTimelineEvent {
        LifeTimelineEvent(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            detailLines: detailLines,
            date: date,
            estimatedMinutes: estimatedMinutes,
            isCompleted: isCompleted,
            isFixed: isFixed,
            timeConstraint: timeConstraint,
            completedAt: completedAt,
            sortPriority: sortPriority,
            scheduleKind: scheduleKind
        )
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
        let timelineTasks = TaskScheduleQuery.tasksForDay(
            from: tasks,
            allTasks: allTasks,
            day: dayAnchor,
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
        var eventSeriesKeys = Set(
            timelineTasks.map { TaskScheduleQuery.seriesKey(for: $0) }
        )

        let activeTasks = timelineTasks.filter { $0.status.isActive && !isShoppingErrandTask($0) }
        let financeTasks = activeTasks.filter { isFinanceTask($0) }
        let nonFinanceTasks = activeTasks.filter { !isFinanceTask($0) && !isShoppingErrandTask($0) }

        for task in nonFinanceTasks {
            guard !OnboardingTaskSeeder.isJunkOnboardingTask(title: task.title, description: task.description) else { continue }
            guard let event = taskEvent(from: task, allTasks: allTasks, now: now, referenceDay: dayAnchor, calendar: calendar) else { continue }
            events.append(event)
            eventTaskIds.insert(task.id)
            eventSeriesKeys.insert(TaskScheduleQuery.seriesKey(for: task))
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
            for med in medications {
                events.append(medicationEvent(from: med, referenceDay: dayAnchor, calendar: calendar))
            }
        }

        for bill in bills where !bill.isPaid {
            guard calendar.isDate(bill.dueDate, inSameDayAs: dayAnchor) else { continue }
            events.append(LifeTimelineEvent(
                id: "bill-\(bill.id)",
                kind: .bill,
                title: humanBillTitle(bill.title),
                subtitle: bill.isOverdue ? "Overdue" : "Due today",
                date: dayAnchor,
                scheduleKind: .flexibleDay
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
                date: dayAnchor,
                scheduleKind: .flexibleDay
            ))
        }

        for event in calendarEvents where calendar.isDate(event.startDate, inSameDayAs: dayAnchor) {
            let minutes: Int?
            if let end = event.endDate {
                minutes = max(15, Int(end.timeIntervalSince(event.startDate) / 60))
            } else {
                minutes = 30
            }
            events.append(LifeTimelineEvent(
                id: "cal-\(event.id)",
                kind: .meeting,
                title: UserFacingCopy.sanitize(event.title).isEmpty ? event.title : UserFacingCopy.sanitize(event.title),
                subtitle: event.timeLabel,
                date: event.startDate,
                estimatedMinutes: minutes,
                isFixed: true
            ))
        }

        for task in timelineCompleted {
            let seriesKey = TaskScheduleQuery.seriesKey(for: task)
            guard !eventTaskIds.contains(task.id) else { continue }
            guard !eventSeriesKeys.contains(seriesKey) else { continue }
            guard let event = taskEvent(from: task, allTasks: allTasks, now: now, referenceDay: dayAnchor, calendar: calendar, forceCompleted: true) else { continue }
            events.append(event)
            eventSeriesKeys.insert(seriesKey)
        }

        if isToday {
            let boundaryContext = DayBoundaryPlanner.Context(
                tasks: tasks + completedToday,
                timelineEvents: events
            )
            if let sleepEvent = DayBoundaryPlanner.sleepTimelineEvent(
                on: dayAnchor,
                now: now,
                calendar: calendar,
                context: boundaryContext
            ) {
                events.append(sleepEvent)
            }
        }

        let filtered = events
            .filter { calendar.isDate($0.date, inSameDayAs: dayAnchor) }
        return TimelineDisplaySort.sorted(filtered, now: now, calendar: calendar)
    }

    // MARK: - Task → event

    /// Active tasks scheduled for today — delegates to `TaskScheduleQuery`.
    public static func tasksScheduledForToday(
        from tasks: [LifeTask],
        allTasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LifeTask] {
        TaskScheduleQuery.tasksForDay(
            from: tasks,
            allTasks: allTasks,
            day: calendar.startOfDay(for: now),
            calendar: calendar
        )
    }

    /// Completed tasks that count toward today's schedule — excludes stale completions.
    public static func completedTasksScheduledForToday(
        from completedToday: [LifeTask],
        allTasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LifeTask] {
        completedTasksForTodayTimeline(
            from: completedToday,
            allTasks: allTasks,
            now: now,
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
            let completionAnchor: Date? = task.completedAt
                ?? (calendar.isDate(task.updatedAt, inSameDayAs: now) ? task.updatedAt : nil)
            guard let completionAnchor, completionAnchor >= startOfDay else { return false }

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

    private static func taskEvent(
        from task: LifeTask,
        allTasks: [LifeTask],
        now: Date,
        referenceDay: Date,
        calendar: Calendar,
        forceCompleted: Bool = false
    ) -> LifeTimelineEvent? {
        let title = timelineTitle(for: task)
        guard !title.isEmpty else { return nil }
        return makeTaskEvent(
            task: task,
            title: title,
            allTasks: allTasks,
            now: now,
            referenceDay: referenceDay,
            calendar: calendar,
            forceCompleted: forceCompleted
        )
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

    private static func makeTaskEvent(
        task: LifeTask,
        title: String,
        allTasks: [LifeTask],
        now: Date,
        referenceDay: Date,
        calendar: Calendar,
        forceCompleted: Bool
    ) -> LifeTimelineEvent {
        let day = calendar.startOfDay(for: referenceDay)
        let hasConcreteSlot = TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: day, calendar: calendar)
        let isFlexibleDay = TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: day, calendar: calendar)
        let isFloatingFlexible = !hasConcreteSlot && !isFlexibleDay
            && (task.schedulingMode == .flexible || task.timeConstraint == .flexible)

        let when: Date
        let isCompletedEvent = forceCompleted || task.status == .completed
        if isCompletedEvent {
            if let displayTime = TaskScheduleInterval.timelineDisplayTime(
                for: task, on: day, calendar: calendar, isCompleted: true
            ) {
                when = displayTime
            } else {
                when = day
            }
        } else if isFlexibleDay || isFloatingFlexible || !hasConcreteSlot {
            when = day
        } else if let start = TaskScheduleInterval.resolvedStart(for: task, on: day, calendar: calendar),
                  !TaskScheduleInterval.isDisplayMidnightSentinel(start, on: day, calendar: calendar) {
            when = start
        } else if TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar)
                    || TaskScheduleInterval.isMidnightClockTime(task.scheduledTime, calendar: calendar) {
            when = day
        } else {
            when = task.deadline ?? task.createdAt
        }
        let kind = LifeTimelineKindResolver.kind(for: task)

        var duration = TaskScheduleInterval.displayDurationMinutes(for: task, on: day, calendar: calendar)
        if duration <= 0 {
            duration = task.estimatedMinutes > 0 ? task.estimatedMinutes : TaskDurationPolicy.minimumMinutes
        }

        let subtitle: String
        if forceCompleted || task.status == .completed {
            subtitle = "Done"
        } else {
            switch TaskScheduleInterval.displaySchedule(for: task, on: day, calendar: calendar) {
            case .unslottedFlexible:
                subtitle = "Flexible today"
            case .window(_, _, let rangeLabel):
                subtitle = rangeLabel
            case .noSchedule:
                if duration > 0 {
                    subtitle = "About \(duration) min"
                } else {
                    subtitle = kind.sectionLabel
                }
            }
        }

        var displaySubtitle = subtitle
        if MultiDayTaskTags.isSlice(task),
           let parentId = task.parentTaskId,
           let parent = allTasks.first(where: { $0.id == parentId }) {
            displaySubtitle = "\(parent.title) · \(subtitle)"
        }

        let scheduleKind: TimelineScheduleKind
        if forceCompleted || task.status == .completed {
            scheduleKind = .completed
        } else if !hasConcreteSlot
                    || isFlexibleDay
                    || isFloatingFlexible
                    || TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar)
                    || TaskScheduleInterval.isMidnightClockTime(task.scheduledTime, calendar: calendar) {
            scheduleKind = (!hasConcreteSlot
                || isFlexibleDay
                || TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar)
                || TaskScheduleInterval.isMidnightClockTime(task.scheduledTime, calendar: calendar))
                ? .flexibleDay : .floating
        } else {
            scheduleKind = .fixedWindow
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
            timeConstraint: task.timeConstraintValue,
            completedAt: task.completedAt,
            sortPriority: task.priority.rawValue,
            scheduleKind: scheduleKind
        )
    }

    public static func kindForTask(_ task: LifeTask) -> LifeTimelineEventKind {
        LifeTimelineKindResolver.kind(for: task)
    }

    // MARK: - Grouped shopping

    private static func groupedShoppingTrip(
        items: [ShoppingItem],
        scheduledTask: LifeTask?,
        now: Date,
        calendar: Calendar
    ) -> LifeTimelineEvent {
        let names = items.map(\.name).sorted()
        if let task = scheduledTask,
           let day = task.scheduledDate.map({ calendar.startOfDay(for: $0) }),
           let time = task.scheduledTime,
           let combined = calendar.combine(date: day, timeFrom: time),
           TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: day, calendar: calendar) {
            let minutes = task.estimatedMinutes
            return LifeTimelineEvent(
                id: "shopping-trip",
                kind: .shopping,
                title: "Stop at the grocery store",
                subtitle: "About \(minutes) minutes",
                detailLines: names,
                date: combined,
                estimatedMinutes: minutes
            )
        }
        let minutes = scheduledTask?.estimatedMinutes ?? min(45, 15 + names.count * 3)
        return LifeTimelineEvent(
            id: "shopping-trip",
            kind: .shopping,
            title: "Stop at the grocery store",
            subtitle: "About \(minutes) minutes",
            detailLines: names,
            date: calendar.startOfDay(for: now),
            estimatedMinutes: minutes,
            scheduleKind: .flexibleDay
        )
    }

    // MARK: - Grouped finance

    private static func groupedFinanceSession(tasks: [LifeTask], now: Date, calendar: Calendar) -> LifeTimelineEvent {
        let lines = tasks.compactMap { task -> String? in
            let headline = HumanLanguage.outcomeHeadline(task: task)
            return UserFacingCopy.isInternalExecutionLabel(headline) ? task.title : headline
        }
        let earliestConcrete = tasks.compactMap { task -> Date? in
            guard let day = task.scheduledDate, let time = task.scheduledTime else { return nil }
            return calendar.combine(date: calendar.startOfDay(for: day), timeFrom: time)
        }.min()
        let when = earliestConcrete ?? calendar.startOfDay(for: now)
        let minutes = tasks.reduce(0) { $0 + max($1.estimatedMinutes, TaskDurationPolicy.minimumMinutes) }
        let hasClock = earliestConcrete != nil
        return LifeTimelineEvent(
            id: "finance-session",
            kind: .finance,
            title: "Finance session",
            subtitle: "About \(minutes) minutes",
            detailLines: lines,
            date: when,
            estimatedMinutes: minutes,
            scheduleKind: hasClock ? .fixedWindow : .flexibleDay
        )
    }

    // MARK: - Medication

    private static func medicationEvent(from med: Medication, referenceDay: Date, calendar: Calendar) -> LifeTimelineEvent {
        let day = calendar.startOfDay(for: referenceDay)
        let scheduledToday = calendar.combine(date: day, timeFrom: med.scheduledTime) ?? med.scheduledTime
        let hour = calendar.component(.hour, from: scheduledToday)
        let period: String
        switch hour {
        case ..<12: period = "Morning"
        case 12..<17: period = "Afternoon"
        default: period = "Evening"
        }
        let instruction = medicationInstruction(name: med.name, dosage: med.dosage)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeLabel = formatter.string(from: scheduledToday)

        return LifeTimelineEvent(
            id: "med-\(med.id)",
            kind: .medication,
            title: "\(period) medication",
            subtitle: med.isTaken ? "Taken · \(instruction)" : "\(timeLabel) · \(instruction)",
            date: med.isTaken ? (med.lastTakenAt ?? scheduledToday) : scheduledToday,
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
        let profile = task.resolvedSemanticProfile
        if profile.subtype == "meal" { return false }
        return task.lifeArea == .shopping
            || profile.semanticType == .errand
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
