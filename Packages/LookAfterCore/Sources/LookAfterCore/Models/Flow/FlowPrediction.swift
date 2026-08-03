import Foundation

/// Pre-computed hero action for the Flow Surface Start/Continue button.
/// Flow Director owns scheduling; this struct carries the decision to the UI layer.
public struct FlowPrediction: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Identifier of the task this prediction applies to (`LifeTask.id`).
    public var taskID: String
    public var suggestedDurationMinutes: Int
    public var buttonLabel: String
    public var buttonSubtitle: String
    /// Confidence in this prediction (0.0–1.0).
    public var confidence: Double
    /// Human-readable reasoning for briefing copy (not settings UI).
    public var reasoning: String
    public var actionType: FlowActionType

    public init(
        id: String = UUID().uuidString,
        taskID: String,
        suggestedDurationMinutes: Int,
        buttonLabel: String,
        buttonSubtitle: String,
        confidence: Double,
        reasoning: String,
        actionType: FlowActionType
    ) {
        self.id = id
        self.taskID = taskID
        self.suggestedDurationMinutes = suggestedDurationMinutes
        self.buttonLabel = buttonLabel
        self.buttonSubtitle = buttonSubtitle
        self.confidence = min(max(confidence, 0), 1)
        self.reasoning = reasoning
        self.actionType = actionType
    }
}

/// Explains a silent reschedule performed by Flow Director.
public struct RescheduleNotice: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var taskID: String
    public var taskTitle: String
    /// User-facing explanation, e.g. "Moved to after lunch—it needs deep focus."
    public var explanation: String

    public init(
        id: String = UUID().uuidString,
        taskID: String,
        taskTitle: String,
        explanation: String
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.explanation = explanation
    }
}

/// Ephemeral behavioral coaching chip (not a chat message).
public struct CoachMoment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var message: String
    public var primaryAction: String
    public var secondaryAction: String
    public var momentType: CoachMomentType

    public init(
        id: String = UUID().uuidString,
        message: String,
        primaryAction: String,
        secondaryAction: String = "Not now",
        momentType: CoachMomentType
    ) {
        self.id = id
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.momentType = momentType
    }
}

/// Lightweight peek at Flow World state shown on the NOW canvas.
public struct FlowWorldPeek: Codable, Sendable, Equatable {
    /// River brightness for the current week (0.0–1.0).
    public var riverBrightness: Double
    /// Life area raw value → plant growth stage (0–10).
    public var activePlantStages: [String: Int]
    public var todayParticleCount: Int

    public init(
        riverBrightness: Double = 0,
        activePlantStages: [String: Int] = [:],
        todayParticleCount: Int = 0
    ) {
        self.riverBrightness = min(max(riverBrightness, 0), 1)
        self.activePlantStages = activePlantStages
        self.todayParticleCount = max(todayParticleCount, 0)
    }

    public static let empty = FlowWorldPeek()
}

/// EventKit bridge type kept in LookAfterCore to avoid EventKit dependency in the core package.
public struct CalendarEventReference: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var minutesUntilStart: Int

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        minutesUntilStart: Int
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.minutesUntilStart = minutesUntilStart
    }
}

/// Snapshot of an active Flow session for orchestration decisions.
/// Populated from `ADHDViewModel` until a dedicated session controller exists.
public struct FlowSessionState: Codable, Sendable, Equatable {
    public var isActive: Bool
    public var taskID: String?
    public var elapsedSeconds: Int
    public var targetSeconds: Int
    public var isPaused: Bool
    public var isResting: Bool

    public init(
        isActive: Bool = false,
        taskID: String? = nil,
        elapsedSeconds: Int = 0,
        targetSeconds: Int = 0,
        isPaused: Bool = false,
        isResting: Bool = false
    ) {
        self.isActive = isActive
        self.taskID = taskID
        self.elapsedSeconds = elapsedSeconds
        self.targetSeconds = targetSeconds
        self.isPaused = isPaused
        self.isResting = isResting
    }

    public static let inactive = FlowSessionState()
}
