import Foundation

// MARK: - Meaning (Brain thinks here — never English)

/// What to do — language-neutral verb.
public enum DecisionVerb: String, Codable, Sendable, CaseIterable {
    case finish
    case `continue`
    case start
    case fix
    case wrapUp
    case remember
    case plan
    case shop
    case connect
}

/// What it applies to — known integrations or a task reference.
public enum DecisionObjectKind: String, Codable, Sendable, CaseIterable {
    case appleHealthIntegration
    case oauthSignIn
    case searchPerformance
    case shopping
    case dayPlan
    case capture
    case startWork
    case medication
    case deepWork
    case exercise
    case errand
    case genericTask
}

public struct DecisionObject: Codable, Sendable, Equatable {
    public var kind: DecisionObjectKind
    public var rawTitle: String
    public var taskID: String?

    public init(kind: DecisionObjectKind, rawTitle: String, taskID: String? = nil) {
        self.kind = kind
        self.rawTitle = rawTitle
        self.taskID = taskID
    }
}

/// Why it matters — outcome semantics, not prose.
public enum DecisionBenefit: Codable, Sendable, Equatable {
    case unlockHealthInsights
    case unlockSleepInsights
    case clearBiggestBlocker
    case freeTimeBeforeEvent(String)
    case reduceOverdueWeight
    case maintainMomentum
    case openMorning
    case openAfternoon
    case lighterDay
    case none
}

/// Structured decision — the Brain's native output format.
public struct SemanticDecision: Codable, Sendable, Equatable {
    public var verb: DecisionVerb
    public var object: DecisionObject
    public var benefit: DecisionBenefit
    public var estimateMinutes: Int
    public var confidence: Double
    public var progress: Double

    public init(
        verb: DecisionVerb,
        object: DecisionObject,
        benefit: DecisionBenefit = .none,
        estimateMinutes: Int = 20,
        confidence: Double = 0.85,
        progress: Double = 0
    ) {
        self.verb = verb
        self.object = object
        self.benefit = benefit
        self.estimateMinutes = max(1, estimateMinutes)
        self.confidence = min(max(confidence, 0), 1)
        self.progress = min(max(progress, 0), 1)
    }

    public static var pickUp: SemanticDecision {
        SemanticDecision(
            verb: .start,
            object: DecisionObject(kind: .genericTask, rawTitle: "Pick up where you left off"),
            benefit: .none,
            estimateMinutes: 15,
            confidence: 0.5
        )
    }
}

/// Rendered copy for UI — produced only by HumanLanguage, never by the Brain or LLM.
public struct RenderedDecision: Sendable, Equatable {
    public var headline: String
    public var benefitLine: String
    public var durationLine: String
    public var buttonLabel: String

    public init(
        headline: String,
        benefitLine: String = "",
        durationLine: String = "",
        buttonLabel: String? = nil
    ) {
        self.headline = headline
        self.benefitLine = benefitLine
        self.durationLine = durationLine
        self.buttonLabel = buttonLabel ?? headline
    }
}
