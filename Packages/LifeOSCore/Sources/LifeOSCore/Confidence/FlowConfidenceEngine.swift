import Foundation

/// Deterministic confidence scoring for Flow Director orchestration.
public struct FlowConfidenceEngine: FlowConfidenceEngineProtocol {

    public let staleBehaviorMemoryHours: Double
    public let minEventsForBehaviorConfidence: Int

    public init(
        staleBehaviorMemoryHours: Double = 48,
        minEventsForBehaviorConfidence: Int = 5
    ) {
        self.staleBehaviorMemoryHours = staleBehaviorMemoryHours
        self.minEventsForBehaviorConfidence = minEventsForBehaviorConfidence
    }

    public func assess(_ input: FlowConfidenceInput) -> FlowConfidenceAssessment {
        var score = 1.0
        var penalties: [FlowConfidencePenalty] = []
        var boosts: [FlowConfidenceBoost] = []

        let availability = input.signalAvailability
        let director = input.directorInput
        let scheduling = input.scheduling

        if !availability.health {
            applyPenalty(reason: "Missing health data", impact: 0.12, to: &score, penalties: &penalties)
        }

        if !availability.calendar {
            applyPenalty(reason: "Missing calendar data", impact: 0.10, to: &score, penalties: &penalties)
        }

        if !availability.device {
            applyPenalty(reason: "Missing device state", impact: 0.04, to: &score, penalties: &penalties)
        }

        if !availability.weather {
            applyPenalty(reason: "Missing weather data", impact: 0.02, to: &score, penalties: &penalties)
        }

        let behavior = director.behaviorMemory
        if behavior.recordedEventCount == 0 {
            applyPenalty(reason: "No behavior memory yet", impact: 0.08, to: &score, penalties: &penalties)
        } else if behavior.recordedEventCount < minEventsForBehaviorConfidence {
            applyPenalty(reason: "Limited behavior history", impact: 0.05, to: &score, penalties: &penalties)
        }

        let staleThreshold = staleBehaviorMemoryHours * 3600
        if behavior.recordedEventCount > 0,
           director.currentTime.timeIntervalSince(behavior.updatedAt) > staleThreshold {
            applyPenalty(reason: "Stale behavior memory", impact: 0.06, to: &score, penalties: &penalties)
        }

        if hasConflictingSignals(director: director) {
            applyPenalty(reason: "Conflicting energy and recovery signals", impact: 0.10, to: &score, penalties: &penalties)
        }

        if scheduling.heroTask == nil {
            applyPenalty(reason: "No hero task selected", impact: 0.25, to: &score, penalties: &penalties)
        }

        if scheduling.prediction == nil {
            applyPenalty(reason: "No prediction generated", impact: 0.15, to: &score, penalties: &penalties)
        }

        if availability.health && availability.calendar && behavior.recordedEventCount >= minEventsForBehaviorConfidence {
            applyBoost(reason: "Rich signal coverage", impact: 0.05, to: &score, boosts: &boosts)
        }

        if scheduling.prediction?.actionType == .tryMicro {
            applyPenalty(reason: "Repeated deferrals reduce certainty", impact: 0.05, to: &score, penalties: &penalties)
        }

        if scheduling.prediction?.actionType == .continue {
            applyBoost(reason: "Active session continuity", impact: 0.08, to: &score, boosts: &boosts)
        }

        return FlowConfidenceAssessment(
            overallScore: min(max(score, 0), 1),
            penalties: penalties,
            boosts: boosts
        )
    }

    private func hasConflictingSignals(director: FlowDirectorInput) -> Bool {
        let env = director.environmentContext
        let highEnergy = env.energyScore >= 0.7
        let poorSleep = env.sleepQuality == .poor || env.sleepQuality == .fair
        let lowHRV = env.hrvDelta < -0.1
        return highEnergy && (poorSleep || lowHRV)
    }

    private func applyPenalty(
        reason: String,
        impact: Double,
        to score: inout Double,
        penalties: inout [FlowConfidencePenalty]
    ) {
        score -= impact
        penalties.append(FlowConfidencePenalty(reason: reason, impact: impact))
    }

    private func applyBoost(
        reason: String,
        impact: Double,
        to score: inout Double,
        boosts: inout [FlowConfidenceBoost]
    ) {
        score += impact
        boosts.append(FlowConfidenceBoost(reason: reason, impact: impact))
    }
}
