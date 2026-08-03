import Foundation

/// Inputs required to assemble a complete `FlowSurface`.
/// FlowDirector must use this builder — never construct `FlowSurface` manually.
public struct FlowSurfaceBuildInput: Sendable {
    public var scheduling: FlowSchedulingResult
    public var briefing: FlowBriefingCopy
    public var behaviorMemory: BehaviorMemorySnapshot
    public var environmentContext: EnvironmentContext
    public var confidence: FlowConfidenceAssessment
    public var worldPeek: FlowWorldPeek
    public var generatedAt: Date

    public init(
        scheduling: FlowSchedulingResult,
        briefing: FlowBriefingCopy = FlowBriefingCopy(),
        behaviorMemory: BehaviorMemorySnapshot = .empty,
        environmentContext: EnvironmentContext = .baseline,
        confidence: FlowConfidenceAssessment = FlowConfidenceAssessment(overallScore: 0),
        worldPeek: FlowWorldPeek = .empty,
        generatedAt: Date = Date()
    ) {
        self.scheduling = scheduling
        self.briefing = briefing
        self.behaviorMemory = behaviorMemory
        self.environmentContext = environmentContext
        self.confidence = confidence
        self.worldPeek = worldPeek
        self.generatedAt = generatedAt
    }
}

/// Converts scheduling, behavior, environment, and briefing into a publishable `FlowSurface`.
public enum FlowSurfaceBuilder {

    /// Primary build path — merges all orchestration outputs into one surface.
    public static func build(from input: FlowSurfaceBuildInput) -> FlowSurface {
        let scheduling = input.scheduling
        let focusReadiness = adjustedFocusReadiness(
            base: scheduling.focusReadiness,
            environment: input.environmentContext,
            behavior: input.behaviorMemory
        )

        var prediction = scheduling.prediction
        if var pred = prediction {
            pred.confidence = input.confidence.overallScore
            prediction = pred
        }

        return FlowSurface(
            greeting: input.briefing.greeting,
            briefingLines: input.briefing.briefingLines,
            flowPersonality: scheduling.flowPersonality,
            heroTask: scheduling.heroTask,
            prediction: prediction,
            flowWindow: scheduling.flowWindow ?? input.environmentContext.flowWindow,
            nextCalendarEvent: scheduling.nextCalendarEvent ?? input.environmentContext.nextEvent,
            energyScore: scheduling.energyScore,
            focusReadiness: focusReadiness,
            rescheduledTasks: scheduling.rescheduledTasks,
            coachMoment: scheduling.coachMoment,
            worldPeek: input.worldPeek,
            generatedAt: input.generatedAt,
            confidence: input.confidence.overallScore
        )
    }

    /// Convenience API for briefing-only merges (backward compatible with D2.1 tests).
    public static func build(
        scheduling: FlowSchedulingResult,
        briefing: FlowBriefingCopy = FlowBriefingCopy(),
        worldPeek: FlowWorldPeek = .empty,
        generatedAt: Date = Date()
    ) -> FlowSurface {
        build(from: FlowSurfaceBuildInput(
            scheduling: scheduling,
            briefing: briefing,
            confidence: FlowConfidenceAssessment(overallScore: scheduling.confidence),
            worldPeek: worldPeek,
            generatedAt: generatedAt
        ))
    }

    private static func adjustedFocusReadiness(
        base: Double,
        environment: EnvironmentContext,
        behavior: BehaviorMemorySnapshot
    ) -> Double {
        var readiness = base

        if environment.isLowPowerMode {
            readiness -= 0.05
        }
        if environment.focusModeEnabled {
            readiness += 0.05
        }
        if behavior.deferralEventCount > behavior.completionEventCount, behavior.recordedEventCount >= 5 {
            readiness -= 0.08
        }

        return min(max(readiness, 0), 1)
    }
}
