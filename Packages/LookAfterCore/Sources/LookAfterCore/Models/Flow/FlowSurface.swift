import Foundation

/// Immutable render model published by Flow Director for the Flow Canvas and widget surfaces.
/// This is the primary output contract for proactive day orchestration (Phase D2).
public struct FlowSurface: Codable, Sendable, Equatable {
    // MARK: - Briefing

    public var greeting: String
    /// Max 3 lines of proactive briefing copy.
    public var briefingLines: [String]
    public var flowPersonality: FlowPersonality

    // MARK: - Hero Action

    public var heroTask: LifeTask?
    public var prediction: FlowPrediction?

    // MARK: - Context

    public var flowWindow: DateInterval?
    public var nextCalendarEvent: CalendarEventReference?
    public var energyScore: Double
    public var focusReadiness: Double

    // MARK: - Orchestration Transparency

    public var rescheduledTasks: [RescheduleNotice]
    public var coachMoment: CoachMoment?

    // MARK: - Flow World Peek

    public var worldPeek: FlowWorldPeek

    // MARK: - Metadata

    public var generatedAt: Date
    /// Overall confidence in this surface snapshot (0.0–1.0).
    public var confidence: Double

    public init(
        greeting: String = "",
        briefingLines: [String] = [],
        flowPersonality: FlowPersonality = .steady,
        heroTask: LifeTask? = nil,
        prediction: FlowPrediction? = nil,
        flowWindow: DateInterval? = nil,
        nextCalendarEvent: CalendarEventReference? = nil,
        energyScore: Double = 0.5,
        focusReadiness: Double = 0.5,
        rescheduledTasks: [RescheduleNotice] = [],
        coachMoment: CoachMoment? = nil,
        worldPeek: FlowWorldPeek = .empty,
        generatedAt: Date = Date(),
        confidence: Double = 0
    ) {
        self.greeting = greeting
        self.briefingLines = briefingLines
        self.flowPersonality = flowPersonality
        self.heroTask = heroTask
        self.prediction = prediction
        self.flowWindow = flowWindow
        self.nextCalendarEvent = nextCalendarEvent
        self.energyScore = min(max(energyScore, 0), 1)
        self.focusReadiness = min(max(focusReadiness, 0), 1)
        self.rescheduledTasks = rescheduledTasks
        self.coachMoment = coachMoment
        self.worldPeek = worldPeek
        self.generatedAt = generatedAt
        self.confidence = min(max(confidence, 0), 1)
    }

    /// Placeholder surface when orchestration has not yet run.
    public static let empty = FlowSurface()

    /// Whether the surface has enough data to present a hero action.
    public var hasHeroAction: Bool {
        heroTask != nil && prediction != nil
    }

    /// Combined briefing text for widget/Live Activity surfaces.
    public var briefingText: String {
        briefingLines.joined(separator: "\n")
    }
}
