import Foundation

/// Input for confidence calculation after scheduling.
public struct FlowConfidenceInput: Sendable {
    public var directorInput: FlowDirectorInput
    public var scheduling: FlowSchedulingResult
    public var signalAvailability: EnvironmentSignalAvailability

    public init(
        directorInput: FlowDirectorInput,
        scheduling: FlowSchedulingResult,
        signalAvailability: EnvironmentSignalAvailability = EnvironmentSignalAvailability()
    ) {
        self.directorInput = directorInput
        self.scheduling = scheduling
        self.signalAvailability = signalAvailability
    }
}

/// Detailed confidence breakdown for transparency and future UI.
public struct FlowConfidenceAssessment: Sendable, Equatable {
    public var overallScore: Double
    public var penalties: [FlowConfidencePenalty]
    public var boosts: [FlowConfidenceBoost]

    public init(
        overallScore: Double,
        penalties: [FlowConfidencePenalty] = [],
        boosts: [FlowConfidenceBoost] = []
    ) {
        self.overallScore = min(max(overallScore, 0), 1)
        self.penalties = penalties
        self.boosts = boosts
    }
}

public struct FlowConfidencePenalty: Sendable, Equatable {
    public var reason: String
    public var impact: Double

    public init(reason: String, impact: Double) {
        self.reason = reason
        self.impact = min(max(impact, 0), 1)
    }
}

public struct FlowConfidenceBoost: Sendable, Equatable {
    public var reason: String
    public var impact: Double

    public init(reason: String, impact: Double) {
        self.reason = reason
        self.impact = min(max(impact, 0), 1)
    }
}

/// Calculates orchestration confidence from signal availability and scheduling coherence.
public protocol FlowConfidenceEngineProtocol: Sendable {
    func assess(_ input: FlowConfidenceInput) -> FlowConfidenceAssessment
}
