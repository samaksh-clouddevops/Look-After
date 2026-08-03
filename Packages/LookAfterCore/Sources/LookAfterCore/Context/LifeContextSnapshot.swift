import Foundation

// MARK: - Life Context Snapshot

/// Continuously calculated situational model — single source of truth for AI Executive Today.
public struct LifeContextSnapshot: Codable, Sendable, Equatable {
    public var currentEnergy: Double
    public var availableTimeMinutes: Int
    public var location: LocationContext
    public var activeDevices: ActiveDeviceSummary
    public var calendarAvailability: CalendarAvailabilitySummary
    public var sleepQuality: SleepQuality
    public var healthReadiness: Double
    public var currentMission: LifeTask?
    public var lastWorkingContext: WorkingContext?
    public var completionProbability: Double
    public var unpurchasedShoppingCount: Int
    public var calculatedAt: Date

    public init(
        currentEnergy: Double = 0.5,
        availableTimeMinutes: Int = 0,
        location: LocationContext = .unknown,
        activeDevices: ActiveDeviceSummary = .unknown,
        calendarAvailability: CalendarAvailabilitySummary = .open,
        sleepQuality: SleepQuality = .unknown,
        healthReadiness: Double = 0.5,
        currentMission: LifeTask? = nil,
        lastWorkingContext: WorkingContext? = nil,
        completionProbability: Double = 0.5,
        unpurchasedShoppingCount: Int = 0,
        calculatedAt: Date = Date()
    ) {
        self.currentEnergy = min(max(currentEnergy, 0), 1)
        self.availableTimeMinutes = max(availableTimeMinutes, 0)
        self.location = location
        self.activeDevices = activeDevices
        self.calendarAvailability = calendarAvailability
        self.sleepQuality = sleepQuality
        self.healthReadiness = min(max(healthReadiness, 0), 1)
        self.currentMission = currentMission
        self.lastWorkingContext = lastWorkingContext
        self.completionProbability = min(max(completionProbability, 0), 1)
        self.unpurchasedShoppingCount = unpurchasedShoppingCount
        self.calculatedAt = calculatedAt
    }
}

public struct ActiveDeviceSummary: Codable, Sendable, Equatable {
    public var focusModeEnabled: Bool
    public var batteryLevel: Float
    public var isLowPowerMode: Bool
    public var label: String

    public init(
        focusModeEnabled: Bool = false,
        batteryLevel: Float = 1.0,
        isLowPowerMode: Bool = false,
        label: String = "Device ready"
    ) {
        self.focusModeEnabled = focusModeEnabled
        self.batteryLevel = batteryLevel
        self.isLowPowerMode = isLowPowerMode
        self.label = label
    }

    public static let unknown = ActiveDeviceSummary(label: "Device status unknown")
}

public struct CalendarAvailabilitySummary: Codable, Sendable, Equatable {
    public var freeBlockMinutes: Int
    public var nextEventTitle: String?
    public var minutesUntilNextEvent: Int?
    public var hasOpenFlowWindow: Bool

    public init(
        freeBlockMinutes: Int = 0,
        nextEventTitle: String? = nil,
        minutesUntilNextEvent: Int? = nil,
        hasOpenFlowWindow: Bool = false
    ) {
        self.freeBlockMinutes = max(freeBlockMinutes, 0)
        self.nextEventTitle = nextEventTitle
        self.minutesUntilNextEvent = minutesUntilNextEvent
        self.hasOpenFlowWindow = hasOpenFlowWindow
    }

    public static let open = CalendarAvailabilitySummary(freeBlockMinutes: 480, hasOpenFlowWindow: true)
}

// MARK: - Working Context

public enum WorkingContextKind: String, Codable, Sendable, CaseIterable {
    case task
    case focusSession
    case brainCapture
    case aiCoach
    case document
    case note
    case browser
    case file
    case screen
}

public struct WorkingContext: Codable, Sendable, Equatable {
    public var kind: WorkingContextKind
    public var title: String
    public var subtitle: String?
    public var taskID: String?
    public var capturedAt: Date

    public init(
        kind: WorkingContextKind,
        title: String,
        subtitle: String? = nil,
        taskID: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.taskID = taskID
        self.capturedAt = capturedAt
    }
}

// MARK: - Adaptive day emphasis

public enum ExecutiveDayType: String, Codable, Sendable, CaseIterable {
    case workday
    case weekend
    case poorSleep
    case grocery
    case billDue
    case inFlow
    case standard
}

// MARK: - Contextual scroll moments (plain language)

public struct ContextualMoment: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var message: String
    public var icon: String

    public init(id: String = UUID().uuidString, message: String, icon: String) {
        self.id = id
        self.message = message
        self.icon = icon
    }
}

// MARK: - Hero (above the fold)

/// Merged, human-facing hero — no cards, no internal labels.
public struct HeroBriefing: Codable, Sendable, Equatable {
    public var greeting: String
    public var contextLine: String?
    public var actionLine: String
    public var supportingLine: String
    public var outcomeLine: String
    public var whyNowReasons: [String]
    public var buttonLabel: String
    public var action: ContextAction
    public var dayType: ExecutiveDayType
    public var contextualMoments: [ContextualMoment]
    public var dayPreview: [ContextualMoment]
    public var confidenceScore: Double
    public var confidenceLevel: RecommendationConfidenceLevel
    public var durationEstimate: DurationEstimate
    public var insights: [RecommendationInsight]
    public var lowConfidencePrompt: String?
    public var planReadyLine: String?

    public init(
        greeting: String,
        contextLine: String? = nil,
        actionLine: String,
        supportingLine: String,
        outcomeLine: String = "",
        whyNowReasons: [String] = [],
        buttonLabel: String,
        action: ContextAction,
        dayType: ExecutiveDayType = .standard,
        contextualMoments: [ContextualMoment] = [],
        dayPreview: [ContextualMoment] = [],
        confidenceScore: Double = 0.85,
        confidenceLevel: RecommendationConfidenceLevel = .high,
        durationEstimate: DurationEstimate = DurationEstimate(pointMinutes: 20),
        insights: [RecommendationInsight] = [],
        lowConfidencePrompt: String? = nil,
        planReadyLine: String? = nil
    ) {
        self.greeting = greeting
        self.contextLine = contextLine
        self.actionLine = actionLine
        self.supportingLine = supportingLine
        self.outcomeLine = outcomeLine
        self.whyNowReasons = Array(whyNowReasons.prefix(6))
        self.buttonLabel = buttonLabel
        self.action = action
        self.dayType = dayType
        self.contextualMoments = Array(contextualMoments.prefix(3))
        self.dayPreview = Array(dayPreview.prefix(7))
        self.confidenceScore = confidenceScore
        self.confidenceLevel = confidenceLevel
        self.durationEstimate = durationEstimate
        self.insights = insights
        self.lowConfidencePrompt = lowConfidencePrompt
        self.planReadyLine = planReadyLine
    }
}

/// User-facing recommendation card — retained for action wiring.
public struct ActionRecommendation: Codable, Sendable, Equatable {
    public var actionTitle: String
    public var durationLabel: String
    public var whyNowReasons: [String]
    public var expectedOutcome: String
    public var buttonLabel: String
    public var action: ContextAction

    public init(
        actionTitle: String,
        durationLabel: String,
        whyNowReasons: [String],
        expectedOutcome: String,
        buttonLabel: String,
        action: ContextAction
    ) {
        self.actionTitle = actionTitle
        self.durationLabel = durationLabel
        self.whyNowReasons = Array(whyNowReasons.prefix(4))
        self.expectedOutcome = expectedOutcome
        self.buttonLabel = buttonLabel
        self.action = action
    }
}

public struct ContextBriefing: Codable, Sendable, Equatable {
    public var hero: HeroBriefing
    public var todaysStory: TodaysStory?
    public var generatedAt: Date

    public init(hero: HeroBriefing, todaysStory: TodaysStory? = nil, generatedAt: Date = Date()) {
        self.hero = hero
        self.todaysStory = todaysStory
        self.generatedAt = generatedAt
    }

    /// Legacy accessor for tests migrating to hero model.
    public var recommendation: ActionRecommendation {
        ActionRecommendation(
            actionTitle: hero.actionLine,
            durationLabel: hero.supportingLine,
            whyNowReasons: hero.whyNowReasons,
            expectedOutcome: hero.supportingLine,
            buttonLabel: hero.buttonLabel,
            action: hero.action
        )
    }
}

public struct ResumePrompt: Codable, Sendable, Equatable {
    public var title: String
    public var detail: String
    public var taskID: String?

    public init(title: String = "Pick up where you stopped", detail: String, taskID: String? = nil) {
        self.title = title
        self.detail = detail
        self.taskID = taskID
    }
}

public struct ContextAction: Codable, Sendable, Equatable {
    public var label: String
    public var taskID: String?
    public var kind: ContextActionKind

    public init(label: String, taskID: String? = nil, kind: ContextActionKind) {
        self.label = label
        self.taskID = taskID
        self.kind = kind
    }
}

public extension HeroBriefing {
    /// Single-line reason shown under the primary action — prefers calendar/context over generic reasons.
    var primaryWhyLine: String? {
        if let contextLine, !contextLine.isEmpty { return contextLine }
        return whyNowReasons.first
    }
}

public enum ContextActionKind: String, Codable, Sendable {
    case startTask
    case continueTask
    case resumeSession
    case openContinueSession
    case beginWork
    case openShopping
    case openCoach
    case openBrain
    case viewPlan
    case openHealthDetail
}
