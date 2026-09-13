import Foundation

/// Confidence classification for a single AI-extracted field.
///
/// `known`/`inferred` fields carry a value; `ambiguous`/`unknown` fields never do —
/// this keeps "the model wasn't sure" distinguishable from "the model invented a value."
public enum ExtractedFieldStatus: String, Codable, Sendable, Equatable {
    case known
    case inferred
    case ambiguous
    case unknown
}

/// Provenance of an extracted field's value. Present only when status is `known`/`inferred`.
public enum ExtractedFieldSource: String, Codable, Sendable, Equatable {
    /// Taken directly from the input text (e.g. "Friday 2 PM" → scheduledAt).
    case explicitUserText = "explicit_user_text"
    /// Filled from an existing codebase default/policy, not the model's judgment.
    case deterministicPolicy = "deterministic_policy"
    /// The model derived the value from context without an explicit statement or policy.
    case modelInference = "model_inference"
}

/// A single AI-extracted field with status + provenance, so "unknown" is never confused with
/// a fabricated confident value. See Documentation/ai-opportunity-implementation-plan-2026-09.md §2.1.
public struct ExtractedField<Value: Sendable & Equatable>: Sendable, Equatable {
    public var value: Value?
    public var status: ExtractedFieldStatus
    public var source: ExtractedFieldSource?

    public init(value: Value? = nil, status: ExtractedFieldStatus = .unknown, source: ExtractedFieldSource? = nil) {
        self.value = value
        self.status = status
        self.source = source
    }

    public static var unknown: ExtractedField<Value> {
        ExtractedField(value: nil, status: .unknown, source: nil)
    }
}

/// Result of natural-language task capture extraction (R3) — a review-ready draft, not a
/// direct commit. Ambiguous/unknown fields are surfaced to the review UI rather than guessed.
public struct NaturalLanguageTaskDraft: Sendable, Equatable {
    public var title: String
    public var lifeArea: ExtractedField<LifeArea>
    public var priority: ExtractedField<Priority>
    public var difficulty: ExtractedField<TaskDifficulty>
    public var estimatedMinutes: ExtractedField<Int>
    public var deadline: ExtractedField<Date>
    public var scheduledAt: ExtractedField<Date>
    public var timeConstraint: ExtractedField<TimeConstraint>
    /// Cross-field consistency warnings surfaced by the validator (e.g. "scheduledAt-after-deadline").
    public var flaggedInconsistencies: [String]

    public init(
        title: String,
        lifeArea: ExtractedField<LifeArea> = .unknown,
        priority: ExtractedField<Priority> = .unknown,
        difficulty: ExtractedField<TaskDifficulty> = .unknown,
        estimatedMinutes: ExtractedField<Int> = .unknown,
        deadline: ExtractedField<Date> = .unknown,
        scheduledAt: ExtractedField<Date> = .unknown,
        timeConstraint: ExtractedField<TimeConstraint> = .unknown,
        flaggedInconsistencies: [String] = []
    ) {
        self.title = title
        self.lifeArea = lifeArea
        self.priority = priority
        self.difficulty = difficulty
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.scheduledAt = scheduledAt
        self.timeConstraint = timeConstraint
        self.flaggedInconsistencies = flaggedInconsistencies
    }

    /// Bridges to the existing inbox-draft review/commit path — unknown fields fall back to
    /// the same defaults `createFromInbox` already applies (`.personal`/`.medium`/etc.).
    public func toInboxTaskDraft() -> InboxTaskDraft {
        InboxTaskDraft(
            title: title,
            lifeArea: lifeArea.value,
            priority: priority.value,
            difficulty: difficulty.value,
            estimatedMinutes: estimatedMinutes.value ?? TaskDurationPolicy.defaultMinutes
        )
    }
}
