import Foundation

public struct StorySegment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var periodLabel: String
    public var title: String
    public var why: String
    public var estimatedMinutes: Int
    public var confidence: Double
    public var taskID: String?
    public var dependencies: [String]
    public var isCalendarEvent: Bool

    public init(
        id: String = UUID().uuidString,
        periodLabel: String,
        title: String,
        why: String,
        estimatedMinutes: Int,
        confidence: Double = 0.75,
        taskID: String? = nil,
        dependencies: [String] = [],
        isCalendarEvent: Bool = false
    ) {
        self.id = id
        self.periodLabel = periodLabel
        self.title = title
        self.why = why
        self.estimatedMinutes = estimatedMinutes
        self.confidence = confidence
        self.taskID = taskID
        self.dependencies = dependencies
        self.isCalendarEvent = isCalendarEvent
    }
}

/// Narrative daily plan — not a task list.
public struct TodaysStory: Codable, Sendable, Equatable {
    public var greeting: String
    public var narrativeParagraphs: [String]
    public var segments: [StorySegment]
    public var generatedAt: Date
    public var isReady: Bool

    public init(
        greeting: String,
        narrativeParagraphs: [String],
        segments: [StorySegment],
        generatedAt: Date = Date(),
        isReady: Bool = true
    ) {
        self.greeting = greeting
        self.narrativeParagraphs = narrativeParagraphs
        self.segments = segments
        self.generatedAt = generatedAt
        self.isReady = isReady
    }
}

public struct TodaysStoryGenerator: Sendable {
    private let calendar: Calendar
    private let durationEstimator = DurationEstimator()

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public struct Input: Sendable {
        public var snapshot: LifeContextSnapshot
        public var tasks: [LifeTask]
        public var timelineItems: [LifeTimelineEvent]
        public var healthSummary: HealthSummary?
        public var userName: String
        public var now: Date

        public init(
            snapshot: LifeContextSnapshot,
            tasks: [LifeTask],
            timelineItems: [LifeTimelineEvent],
            healthSummary: HealthSummary? = nil,
            userName: String = "",
            now: Date = Date()
        ) {
            self.snapshot = snapshot
            self.tasks = tasks
            self.timelineItems = timelineItems
            self.healthSummary = healthSummary
            self.userName = userName
            self.now = now
        }
    }

    public func generate(_ input: Input) -> TodaysStory {
        let greeting = morningGreeting(userName: input.userName, now: input.now)
        var paragraphs: [String] = []
        var segments: [StorySegment] = []

        if input.snapshot.sleepQuality == .good || input.snapshot.sleepQuality == .excellent {
            paragraphs.append("You slept well.")
        } else if input.snapshot.sleepQuality == .poor || input.snapshot.sleepQuality == .fair {
            paragraphs.append("Last night was rough — we'll keep the morning light.")
        }

        let meetingCount = input.timelineItems.filter {
            $0.kind == .meeting && calendar.isDate($0.date, inSameDayAs: input.now) && !$0.isCompleted
        }.count
        if meetingCount >= 3 {
            paragraphs.append("Today is meeting-heavy.")
        } else if meetingCount == 0 {
            paragraphs.append("Your calendar has breathing room today.")
        }

        let activeTasks = input.tasks.filter { $0.status.isActive }
            .sorted { lhs, rhs in
                if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return (lhs.deadline ?? .distantFuture) < (rhs.deadline ?? .distantFuture)
            }

        let calendarToday = input.timelineItems
            .filter { $0.kind == .meeting && calendar.isDate($0.date, inSameDayAs: input.now) && !$0.isCompleted }
            .sorted { $0.date < $1.date }

        var slotIndex = 0
        let periods = ["Morning", "Before Lunch", "Afternoon", "Evening", "Night"]

        for task in activeTasks.prefix(4) {
            let period = periods[min(slotIndex, periods.count - 1)]
            let estimate = durationEstimator.estimate(
                DurationEstimator.Input(task: task, snapshot: input.snapshot, healthSummary: input.healthSummary)
            )
            let why = whyForTask(task, snapshot: input.snapshot)
            segments.append(StorySegment(
                id: "story-\(task.id)",
                periodLabel: period,
                title: task.title,
                why: why,
                estimatedMinutes: estimate.pointMinutes,
                confidence: estimate.confidence,
                taskID: task.id
            ))
            slotIndex += 1
        }

        for event in calendarToday.prefix(3) {
            let period = periodLabel(for: event.date, now: input.now)
            segments.append(StorySegment(
                id: "story-\(event.id)",
                periodLabel: period,
                title: event.title,
                why: "On your calendar",
                estimatedMinutes: 30,
                confidence: 0.95,
                isCalendarEvent: true
            ))
        }

        segments.sort { periodOrder($0.periodLabel) < periodOrder($1.periodLabel) }

        if let first = segments.first(where: { !$0.isCalendarEvent }) {
            paragraphs.append("I recommend finishing \(first.title.lowercased()) in the \(first.periodLabel.lowercased()).")
        }
        if segments.count > 1, let second = segments.dropFirst().first(where: { !$0.isCalendarEvent }) {
            paragraphs.append("After that, \(second.title.lowercased()) fits naturally.")
        }

        if paragraphs.isEmpty {
            paragraphs.append("Today's plan is ready whenever you are.")
        }

        return TodaysStory(
            greeting: greeting,
            narrativeParagraphs: paragraphs,
            segments: segments,
            isReady: !segments.isEmpty
        )
    }

    private func morningGreeting(userName: String, now: Date) -> String {
        let hour = calendar.component(.hour, from: now)
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        default: base = "Good evening"
        }
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? base : "\(base), \(name)"
    }

    private func whyForTask(_ task: LifeTask, snapshot: LifeContextSnapshot) -> String {
        if task.isOverdue { return "Overdue — clearing this reduces stress" }
        if let deadline = task.deadline {
            if calendar.isDateInToday(deadline) { return "Due today" }
        }
        if let event = snapshot.calendarAvailability.nextEventTitle,
           let mins = snapshot.calendarAvailability.minutesUntilNextEvent, mins <= 120 {
            return "Finish before \(event)"
        }
        return "Best next step for your energy right now"
    }

    private func periodLabel(for date: Date, now: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return "Morning"
        case 11..<14: return "Before Lunch"
        case 14..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    private func periodOrder(_ label: String) -> Int {
        switch label {
        case "Morning": return 0
        case "Before Lunch": return 1
        case "Afternoon": return 2
        case "Evening": return 3
        default: return 4
        }
    }
}
