import Foundation

/// A planned block in the user's day — built by the Brain, not the UI.
public struct PlanBlock: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var startLabel: String
    public var title: String
    public var kind: PlanBlockKind
    public var reasoning: String?

    public init(
        id: String = UUID().uuidString,
        startLabel: String,
        title: String,
        kind: PlanBlockKind,
        reasoning: String? = nil
    ) {
        self.id = id
        self.startLabel = startLabel
        self.title = title
        self.kind = kind
        self.reasoning = reasoning
    }
}

public enum PlanBlockKind: String, Codable, Sendable {
    case medication
    case meal
    case travel
    case meeting
    case deepWork
    case lightWork
    case exercise
    case rest
    case personal
}

public struct DayPlan: Codable, Sendable, Equatable {
    public var blocks: [PlanBlock]
    public var narrativeSummary: String
    public var generatedAt: Date

    public init(
        blocks: [PlanBlock] = [],
        narrativeSummary: String = "",
        generatedAt: Date = Date()
    ) {
        self.blocks = blocks
        self.narrativeSummary = narrativeSummary
        self.generatedAt = generatedAt
    }
}
