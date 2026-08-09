import Foundation

/// Status of a task.
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case paused = "Paused"
    case completed = "Completed"
    case skipped = "Skipped"
    case deferred = "Deferred"
    /// Ephemeral window missed — not a failure, a contextual kill.
    case expired = "Expired"
    /// Semantic collision dropped this instance (duplicate already on the day).
    case superseded = "Superseded"

    public var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "arrow.right.circle"
        case .deferred: return "clock.arrow.circlepath"
        case .expired: return "xmark.circle"
        case .superseded: return "arrow.triangle.merge"
        }
    }

    public var isActive: Bool {
        self == .pending || self == .inProgress || self == .paused
    }
}

/// How a task should be offered again after its current occurrence is completed.
/// A repeating task is kept as the original template; future occurrences point
/// back to that template through `parentTaskId`.
public enum TaskRecurrence: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case none = "Does not repeat"
    case daily = "Every day"
    case weekdays = "Weekdays"
    case weekends = "Weekends"
    case weekly = "Every week"
    case monthly = "Every month"
    case yearly = "Every year"
    case custom = "Custom"

    public var id: String { rawValue }

    public func occurs(
        on date: Date,
        anchoredOn anchor: Date,
        interval: Int = 1,
        weekdays: [Int]? = nil,
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        let anchorDay = calendar.startOfDay(for: anchor)
        guard day >= anchorDay else { return false }

        let step = max(interval, 1)

        switch self {
        case .none:
            return false
        case .daily:
            let days = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
            return days % step == 0
        case .weekdays:
            return !calendar.isDateInWeekend(day)
        case .weekends:
            return calendar.isDateInWeekend(day)
        case .weekly:
            guard calendar.component(.weekday, from: day) == calendar.component(.weekday, from: anchorDay) else {
                return false
            }
            let days = calendar.dateComponents([.day], from: anchorDay, to: day).day ?? 0
            return days >= 0 && (days / 7) % step == 0
        case .monthly:
            guard calendar.component(.day, from: day) == calendar.component(.day, from: anchorDay) else {
                return false
            }
            let months = calendar.dateComponents([.month], from: anchorDay, to: day).month ?? 0
            return months >= 0 && months % step == 0
        case .yearly:
            guard calendar.component(.month, from: day) == calendar.component(.month, from: anchorDay),
                  calendar.component(.day, from: day) == calendar.component(.day, from: anchorDay) else {
                return false
            }
            let years = calendar.dateComponents([.year], from: anchorDay, to: day).year ?? 0
            return years >= 0 && years % step == 0
        case .custom:
            guard let weekdays, !weekdays.isEmpty else { return false }
            return weekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    /// Returns the next calendar day on or after `after` that satisfies this recurrence rule.
    public func nextOccurrence(
        after date: Date,
        anchoredOn anchor: Date,
        interval: Int = 1,
        weekdays: [Int]? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        guard self != .none else { return nil }

        var candidate = calendar.startOfDay(for: date)
        candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate

        for _ in 0..<730 {
            if occurs(on: candidate, anchoredOn: anchor, interval: interval, weekdays: weekdays, calendar: calendar) {
                return candidate
            }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return nil
    }
}

/// A 5-minute actionable micro-step within a task.
public struct TaskStep: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var isCompleted: Bool
    public var estimatedMinutes: Int
    public var completedAt: Date?
    public var actualMinutes: Int?
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        isCompleted: Bool = false,
        estimatedMinutes: Int = 5,
        completedAt: Date? = nil,
        actualMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.estimatedMinutes = estimatedMinutes
        self.completedAt = completedAt
        self.actualMinutes = actualMinutes
    }
}

/// A task in the LifeOS system.
/// Tasks are energy-aware, decomposable into micro-steps, and AI-prioritized.
public struct LifeTask: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var description: String
    public var lifeArea: LifeArea
    public var priority: Priority
    public var difficulty: TaskDifficulty
    public var status: TaskStatus
    public var steps: [TaskStep]
    public var estimatedMinutes: Int
    /// Floor for cascade compress — below this the block is useless (therapy, deep work).
    /// Optional for backward-compatible decode; resolved via `minimumViableDurationValue`.
    public var minimumViableDuration: Int?
    public var actualMinutes: Int?
    public var requiredEnergy: EnergyLevel
    public var deadline: Date?
    public var scheduledDate: Date?
    public var scheduledTime: Date?
    public var tags: [String]
    public var notes: String
    public var completionProbability: Double?
    public var aiReasoningNote: String?
    public var sourceInboxItemId: String?
    public var parentTaskId: String?
    /// Optional to preserve compatibility with tasks created before recurrence existed.
    public var recurrence: TaskRecurrence?
    /// Custom interval multiplier for recurrence (e.g. every 2 weeks).
    public var recurrenceInterval: Int?
    /// Selected weekdays when recurrence is `.custom` (1 = Sunday … 7 = Saturday).
    public var recurrenceWeekdays: [Int]?
    /// Whether the scheduler may move this task.
    public var schedulingMode: TaskSchedulingMode?
    /// Semantic time lock for timeline physics (anchored / flexible / fluid).
    /// Optional for backward-compatible decode of older task payloads.
    public var timeConstraint: TimeConstraint?
    /// When incomplete instances die (meals / meds / infinite work).
    public var expirationPolicy: TaskExpirationPolicy?
    /// Same-day start fence (e.g. lunch 11–15).
    public var temporalBoundingBox: TemporalBoundingBox?
    /// Rollover vs duplicate-on-destination-day policy.
    public var collisionStrategy: SemanticCollisionStrategy?
    /// Fixed end time-of-day for fixed-time events.
    public var scheduledEndTime: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var userId: String
    /// Master recurrence rule holder — not shown in daily task lists.
    public var isRecurrenceTemplate: Bool?
    /// Structured meaning — computed once at create/edit; schedulers read this, not the title.
    public var semanticProfile: TaskSemanticProfile?
    /// EventKit identifier for the Apple Calendar block mirroring this task.
    public var calendarEventIdentifier: String?
    /// Set when the user manually placed this task on the timeline — drift correction skips it.
    public var userPlacedScheduleAt: Date?
    /// Stable anchor from compiled `DayStructure` (e.g. `routine.dinner`).
    public var scheduleAnchorID: String?
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        lifeArea: LifeArea = .personal,
        priority: Priority = .medium,
        difficulty: TaskDifficulty = .medium,
        status: TaskStatus = .pending,
        steps: [TaskStep] = [],
        estimatedMinutes: Int = 30,
        minimumViableDuration: Int? = nil,
        actualMinutes: Int? = nil,
        requiredEnergy: EnergyLevel = .moderate,
        deadline: Date? = nil,
        scheduledDate: Date? = nil,
        scheduledTime: Date? = nil,
        tags: [String] = [],
        notes: String = "",
        completionProbability: Double? = nil,
        aiReasoningNote: String? = nil,
        sourceInboxItemId: String? = nil,
        parentTaskId: String? = nil,
        recurrence: TaskRecurrence? = nil,
        recurrenceInterval: Int? = nil,
        recurrenceWeekdays: [Int]? = nil,
        schedulingMode: TaskSchedulingMode? = nil,
        timeConstraint: TimeConstraint? = nil,
        expirationPolicy: TaskExpirationPolicy? = nil,
        temporalBoundingBox: TemporalBoundingBox? = nil,
        collisionStrategy: SemanticCollisionStrategy? = nil,
        scheduledEndTime: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        userId: String = "",
        isRecurrenceTemplate: Bool? = nil,
        semanticProfile: TaskSemanticProfile? = nil,
        calendarEventIdentifier: String? = nil,
        userPlacedScheduleAt: Date? = nil,
        scheduleAnchorID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.lifeArea = lifeArea
        self.priority = priority
        self.difficulty = difficulty
        self.status = status
        self.steps = steps
        self.estimatedMinutes = estimatedMinutes
        self.minimumViableDuration = minimumViableDuration
        self.actualMinutes = actualMinutes
        self.requiredEnergy = requiredEnergy
        self.deadline = deadline
        self.scheduledDate = scheduledDate
        self.scheduledTime = scheduledTime
        self.tags = tags
        self.notes = notes
        self.completionProbability = completionProbability
        self.aiReasoningNote = aiReasoningNote
        self.sourceInboxItemId = sourceInboxItemId
        self.parentTaskId = parentTaskId
        self.recurrence = recurrence
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceWeekdays = recurrenceWeekdays
        self.schedulingMode = schedulingMode
        // Prefer explicit constraint; otherwise derive from scheduling mode.
        self.timeConstraint = timeConstraint ?? TimeConstraint.from(schedulingMode: schedulingMode)
        self.expirationPolicy = expirationPolicy
        self.temporalBoundingBox = temporalBoundingBox
        self.collisionStrategy = collisionStrategy
        self.scheduledEndTime = scheduledEndTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.userId = userId
        self.isRecurrenceTemplate = isRecurrenceTemplate
        self.semanticProfile = semanticProfile
        self.calendarEventIdentifier = calendarEventIdentifier
        self.userPlacedScheduleAt = userPlacedScheduleAt
        self.scheduleAnchorID = scheduleAnchorID
    }
    
    // MARK: - Computed Properties
    
    /// Progress as a fraction (0.0 to 1.0) based on completed steps.
    public var progress: Double {
        guard !steps.isEmpty else { return status == .completed ? 1.0 : 0.0 }
        let completedCount = steps.filter(\.isCompleted).count
        return Double(completedCount) / Double(steps.count)
    }
    
    /// Whether the task is overdue (deadline or scheduled day has passed).
    public var isOverdue: Bool {
        guard status.isActive else { return false }
        if let deadline, deadline < Date() { return true }
        if let scheduledDate {
            let today = Calendar.current.startOfDay(for: Date())
            return Calendar.current.startOfDay(for: scheduledDate) < today
        }
        return false
    }
    
    /// Remaining estimated time based on incomplete steps.
    public var remainingMinutes: Int {
        let remaining = steps.filter { !$0.isCompleted }
        return remaining.reduce(0) { $0 + $1.estimatedMinutes }
    }
    
    /// Whether this task is suitable for the given energy level.
    public func isSuitableForEnergy(_ energy: EnergyLevel) -> Bool {
        return energy >= requiredEnergy
    }

    public var recurrenceRule: TaskRecurrence {
        recurrence ?? .none
    }

    public var recurrenceIntervalValue: Int {
        max(recurrenceInterval ?? 1, 1)
    }

    /// Root template id for a recurring series.
    public var templateTaskId: String {
        parentTaskId ?? id
    }

    public var isRecurring: Bool {
        recurrenceRule != .none
    }

    public var isRecurrenceTemplateTask: Bool {
        TaskRecurrenceEngine.isRecurrenceTemplate(self)
    }

    public var isRecurrenceOccurrence: Bool {
        parentTaskId != nil
    }

    public var isCompleted: Bool {
        status == .completed
    }
}
