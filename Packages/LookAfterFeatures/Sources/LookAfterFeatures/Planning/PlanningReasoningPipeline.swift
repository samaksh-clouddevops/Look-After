import Foundation
import LookAfterCore

// MARK: - Intent classification

public enum PlanningIntent: String, Codable, Sendable, CaseIterable {
    case goal
    case task
    case reminder
    case habit
    case appointment
    case shopping
    case medication
    case project
    case idea
    case question
    case reflection
    case replan
    case negotiate
    case energyAdapt
    case travel
    case outcome
    case postWake
    case goingOut
    case reschedule

    public var label: String {
        switch self {
        case .goal: return "Goal"
        case .task: return "Task"
        case .reminder: return "Reminder"
        case .habit: return "Habit"
        case .appointment: return "Appointment"
        case .shopping: return "Shopping"
        case .medication: return "Medication"
        case .project: return "Project"
        case .idea: return "Idea"
        case .question: return "Question"
        case .reflection: return "Reflection"
        case .replan: return "Replan"
        case .negotiate: return "Negotiate"
        case .energyAdapt: return "Energy adapt"
        case .travel: return "Travel"
        case .outcome: return "Outcome"
        case .postWake: return "Post wake"
        case .goingOut: return "Going out"
        case .reschedule: return "Reschedule"
        }
    }
}

public struct PlanningReasoningResult: Sendable {
    public var intent: PlanningIntent
    public var thinkingSteps: [String]
    public var capacityMinutesNeeded: Int
    public var isOverloaded: Bool
    public var existingTaskMatches: [LifeTask]
    public var deferCandidates: [LifeTask]
    public var multiDayDetection: MultiDayDetectionResult?
    public var proactiveSuggestions: [ScheduleProactiveSuggestion]
    public var shouldProposeVariants: Bool

    public init(
        intent: PlanningIntent,
        thinkingSteps: [String],
        capacityMinutesNeeded: Int = 0,
        isOverloaded: Bool = false,
        existingTaskMatches: [LifeTask] = [],
        deferCandidates: [LifeTask] = [],
        multiDayDetection: MultiDayDetectionResult? = nil,
        proactiveSuggestions: [ScheduleProactiveSuggestion] = [],
        shouldProposeVariants: Bool = false
    ) {
        self.intent = intent
        self.thinkingSteps = thinkingSteps
        self.capacityMinutesNeeded = capacityMinutesNeeded
        self.isOverloaded = isOverloaded
        self.existingTaskMatches = existingTaskMatches
        self.deferCandidates = deferCandidates
        self.multiDayDetection = multiDayDetection
        self.proactiveSuggestions = proactiveSuggestions
        self.shouldProposeVariants = shouldProposeVariants
    }
}

/// Deterministic pre-LLM reasoning — intent, capacity, and thinking steps.
public enum PlanningReasoningPipeline {
    public static func analyze(message: String, context: PlanningConversationContext) -> PlanningReasoningResult {
        let intent = classify(message)
        let multiDay = MultiDayTaskDetector.detect(in: message)
        let matches = findExistingMatches(message: message, tasks: context.tasks)
        let needed = estimateMinutes(for: message, intent: intent, multiDay: multiDay)
        let scheduledLoad = context.tasks
            .filter { $0.status.isActive }
            .reduce(0) { $0 + $1.estimatedMinutes }
        let overloaded = needed > 0 && (scheduledLoad + needed) > context.availableMinutes
        let deferCandidates = overloaded
            ? context.tasks.filter { !$0.isFixedTimeEvent && $0.status.isActive }.prefix(3).map { $0 }
            : []

        var steps = baseSteps(for: intent, context: context, multiDay: multiDay)
        if multiDay.isMultiDay {
            steps.append("Multi-day goal detected — planning conversation")
        }
        if !matches.isEmpty {
            steps.append("Found existing plan to reuse")
        }
        if overloaded {
            steps.append("Day looks tight — preparing trade-offs")
        }
        let proactive = ScheduleProactiveAnalyzer.analyze(
            ScheduleProactiveAnalyzer.Input(
                tasks: context.tasks,
                profile: context.lifeProfile,
                now: Date(),
                energyPercent: context.energyPercent,
                completedTodayCount: context.completedTodayCount
            )
        )
        if let top = proactive.first {
            steps.append("Flagging: \(top.message)")
        }
        steps.append("Choosing lowest executive cost")

        let proposeVariants = (overloaded && !multiDay.isMultiDay)
            || intent == .replan
            || intent == .negotiate
            || intent == .postWake

        return PlanningReasoningResult(
            intent: multiDay.isMultiDay ? .project : intent,
            thinkingSteps: steps,
            capacityMinutesNeeded: needed,
            isOverloaded: overloaded && !multiDay.isMultiDay,
            existingTaskMatches: matches,
            deferCandidates: deferCandidates,
            multiDayDetection: multiDay.isMultiDay ? multiDay : nil,
            proactiveSuggestions: proactive,
            shouldProposeVariants: proposeVariants
        )
    }

    // MARK: - Classification

    public static func classify(_ message: String) -> PlanningIntent {
        let lower = message.lowercased()

        if lower.contains("woke up") || lower.contains("just woke") || lower.contains("overslept") || lower.contains("woke late") {
            return .postWake
        }
        if lower.contains("going out") || lower.contains("leaving at") || lower.contains("heading out") || lower.contains("leave at") {
            return .goingOut
        }
        if isRescheduleMessage(lower) {
            return .reschedule
        }
        if lower.contains("medication") || lower.contains("levothyroxine") || lower.contains("thyroid") || lower.contains("took my") && lower.contains("pill") {
            return .medication
        }
        if lower.contains("travel") || lower.contains("flight") || lower.contains("trip to") || lower.contains("airport") {
            return .travel
        }
        if lower.contains("this month") || lower.contains("this week") && !lower.contains("today") || lower.contains("goal") {
            return .goal
        }
        if lower.contains("before the weekend") || lower.contains("finish everything") {
            return .outcome
        }
        if lower.contains("meeting") && (lower.contains("added") || lower.contains("scheduled")) {
            return .appointment
        }
        if lower.contains("exhausted") || lower.contains("tired") || lower.contains("don't feel like") || lower.contains("dont feel like") {
            return .energyAdapt
        }
        if lower.contains("only have") && (lower.contains("minute") || lower.contains("min")) {
            return .replan
        }
        if lower.contains("finished earlier") || lower.contains("done early") || lower.contains("ahead of schedule") {
            return .replan
        }
        if lower.contains("don't want") || lower.contains("dont want") || lower.contains("not today") || lower.contains("postpone") {
            return .negotiate
        }
        if lower.contains("remember to buy") || lower.contains("batteries") || lower.contains("shopping") || lower.contains("groceries") {
            return .shopping
        }
        if lower.contains("?") && lower.split(separator: " ").count < 12 {
            return .question
        }
        if lower.contains("i think") || lower.contains("feeling") || lower.contains("worried") {
            return .reflection
        }
        return .task
    }

    // MARK: - Helpers

    private static func baseSteps(for intent: PlanningIntent, context: PlanningConversationContext, multiDay: MultiDayDetectionResult) -> [String] {
        var steps = ["Understanding intent · \(multiDay.isMultiDay ? "Multi-day project" : intent.label)", "Reading today's timeline"]
        if !context.medications.isEmpty {
            steps.append("Checking medication schedule")
        }
        if context.nextMeetingTitle != nil {
            steps.append("Reviewing meetings")
        }
        steps.append("Assessing capacity · \(context.executiveCapacityLabel)")
        steps.append("Calculating free time · \(context.availableMinutes)m")
        return steps
    }

    private static func findExistingMatches(message: String, tasks: [LifeTask]) -> [LifeTask] {
        TaskDuplicateMatcher.findMatches(for: message, in: tasks)
    }

    private static func estimateMinutes(for message: String, intent: PlanningIntent, multiDay: MultiDayDetectionResult) -> Int {
        if multiDay.isMultiDay { return 0 }
        if let explicit = TaskDurationPolicy.parseExplicitMinutes(from: message) {
            return explicit
        }
        switch intent {
        case .shopping, .medication, .reminder: return 15
        case .replan, .energyAdapt: return 0
        case .reschedule: return 0
        case .goal, .outcome, .travel: return 0
        default:
            let count = message.components(separatedBy: " and ").count + message.components(separatedBy: ",").count
            return min(120, max(5, count * 10))
        }
    }

    private static func isRescheduleMessage(_ lower: String) -> Bool {
        let signals = [
            "move ", "reschedule", "shift ", "push ", "pull forward",
            "earlier", "later", " at ", " to ", "change time"
        ]
        guard signals.contains(where: { lower.contains($0) }) else { return false }
        return lower.contains("move")
            || lower.contains("reschedule")
            || lower.contains("shift")
            || lower.contains("push")
            || lower.contains("earlier")
            || lower.contains("later")
            || PlanningTimeParser.parseHourMinute(from: lower) != nil
    }
}
