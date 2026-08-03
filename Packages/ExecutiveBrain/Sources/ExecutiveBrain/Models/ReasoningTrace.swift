import Foundation

/// One observed fact the Brain weighed — never LLM-generated.
public struct ReasoningFactor: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var domain: WorldDomain
    public var observation: String
    public var impact: ReasoningImpact
    public var weight: Double

    public init(
        id: String = UUID().uuidString,
        domain: WorldDomain,
        observation: String,
        impact: ReasoningImpact,
        weight: Double = 1.0
    ) {
        self.id = id
        self.domain = domain
        self.observation = observation
        self.impact = impact
        self.weight = min(max(weight, 0), 1)
    }
}

public enum ReasoningImpact: String, Codable, Sendable {
    case supports
    case opposes
    case constrains
    case neutral
}

/// Structured reasoning output — the Brain's internal monologue.
public struct ReasoningTrace: Codable, Sendable, Equatable {
    public var factors: [ReasoningFactor]
    public var conclusions: [String]
    public var generatedAt: Date

    public init(
        factors: [ReasoningFactor] = [],
        conclusions: [String] = [],
        generatedAt: Date = Date()
    ) {
        self.factors = factors
        self.conclusions = conclusions
        self.generatedAt = generatedAt
    }
}

public enum WorldDomain: String, Codable, Sendable, CaseIterable {
    case sleep
    case energy
    case calendar
    case medication
    case tasks
    case location
    case weather
    case travel
    case finance
    case shopping
    case habits
    case focus
    case resume
    case relationships
}
