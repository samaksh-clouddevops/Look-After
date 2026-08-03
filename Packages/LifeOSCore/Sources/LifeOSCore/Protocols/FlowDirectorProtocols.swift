import Foundation
import Combine

// MARK: - Flow Director

/// Orchestrates the user's day proactively and publishes a `FlowSurface` snapshot.
/// Implemented in LifeOSAI (milestone D2.4+). UI and widgets observe `surface`.
@MainActor
public protocol FlowDirectorProtocol: ObservableObject {
    /// Latest orchestrated surface for Flow Canvas and widget consumption.
    var surface: FlowSurface { get }
    /// True while an orchestration cycle or LLM briefing refresh is in flight.
    var isOrchestrating: Bool { get }

    /// Run a full orchestration cycle (scheduling + optional LLM copy).
    func orchestrate() async

    /// Re-orchestrate after a task completion event.
    func handleTaskCompleted(_ task: LifeTask) async

    /// Re-orchestrate after a deferral / "not now" event.
    func handleTaskDeferred(_ task: LifeTask) async

    /// Re-orchestrate after a Flow session ends.
    func handleFlowSessionEnded(durationMinutes: Int) async
}

// MARK: - Behavior Memory (Pure Event Store)

/// Append-only behavioral event persistence.
///
/// **This type must never perform analytics or inference.**
/// Use `BehaviorMemorySnapshotBuilder` for deterministic aggregation and
/// `BehaviorAnalysisEngineProtocol` for pattern detection (future).
public protocol BehaviorMemoryStoreProtocol: Sendable {
    func recordCompletion(task: LifeTask, durationMinutes: Int, context: EnvironmentContext) async
    func recordDeferral(task: LifeTask, context: EnvironmentContext?) async
    func recordFlowSession(task: LifeTask?, durationMinutes: Int, context: EnvironmentContext) async

    /// Returns all persisted raw events in append order.
    func fetchEvents() async -> [BehaviorEvent]

    /// Total persisted event count.
    func eventCount() async -> Int

    /// Applies retention policy — removes eligible events from the active envelope.
    /// Archival backends are invoked via `BehaviorMemoryArchivalHandlerProtocol` (future).
    func performRetentionCleanup(
        policy: BehaviorMemoryRetentionPolicy,
        strategy: BehaviorMemoryArchivalStrategy,
        archivalHandler: BehaviorMemoryArchivalHandlerProtocol
    ) async -> BehaviorMemoryCleanupReport
}

/// Persistence backend for Behavior Memory storage documents.
///
/// Defined in LifeOSCore so CloudKit or other backends can be injected from any package
/// without coupling domain logic to file I/O.
public protocol BehaviorMemoryPersistenceBackendProtocol: Sendable {
    /// Loads raw envelope bytes. Returns `nil` when no file exists yet.
    func loadData() async throws -> Data?

    /// Atomically persists envelope bytes.
    func saveData(_ data: Data) async throws
}

// MARK: - Environment Context

/// Builds fused environment signals for Flow Director input (milestone D2.3).
/// Prefer `EnvironmentContextProviding` when availability metadata is required.
public protocol EnvironmentContextProviderProtocol: Sendable {
    func currentContext(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?
    ) async -> EnvironmentContext
}

// MARK: - Flow Scheduling (Pure Logic)

/// Pure scheduling functions with no LLM or UI dependencies.
/// Enables unit testing of orchestration rules independent of FlowDirector.
public protocol FlowSchedulingEngineProtocol: Sendable {
    /// Select hero task and prediction from director input without AI copy.
    func schedule(from input: FlowDirectorInput) -> FlowSchedulingResult
}

/// Deterministic output of the scheduling engine before LLM briefing enrichment.
public struct FlowSchedulingResult: Codable, Sendable, Equatable {
    public var heroTask: LifeTask?
    public var prediction: FlowPrediction?
    public var flowPersonality: FlowPersonality
    public var rescheduledTasks: [RescheduleNotice]
    public var coachMoment: CoachMoment?
    public var flowWindow: DateInterval?
    public var nextCalendarEvent: CalendarEventReference?
    public var energyScore: Double
    public var focusReadiness: Double
    public var confidence: Double

    public init(
        heroTask: LifeTask? = nil,
        prediction: FlowPrediction? = nil,
        flowPersonality: FlowPersonality = .steady,
        rescheduledTasks: [RescheduleNotice] = [],
        coachMoment: CoachMoment? = nil,
        flowWindow: DateInterval? = nil,
        nextCalendarEvent: CalendarEventReference? = nil,
        energyScore: Double = 0.5,
        focusReadiness: Double = 0.5,
        confidence: Double = 0
    ) {
        self.heroTask = heroTask
        self.prediction = prediction
        self.flowPersonality = flowPersonality
        self.rescheduledTasks = rescheduledTasks
        self.coachMoment = coachMoment
        self.flowWindow = flowWindow
        self.nextCalendarEvent = nextCalendarEvent
        self.energyScore = min(max(energyScore, 0), 1)
        self.focusReadiness = min(max(focusReadiness, 0), 1)
        self.confidence = min(max(confidence, 0), 1)
    }
}

// MARK: - Briefing Copy (LLM)

/// LLM-generated copy layered onto a deterministic scheduling result.
public struct FlowBriefingCopy: Codable, Sendable, Equatable {
    public var greeting: String
    public var briefingLines: [String]

    public init(greeting: String = "", briefingLines: [String] = []) {
        self.greeting = greeting
        self.briefingLines = briefingLines
    }
}

/// Generates natural-language briefing lines from a scheduling result.
/// Implemented via `ExecutiveBrain` / `GLMService` (milestone D2.5).
public protocol FlowBriefingProviderProtocol: Sendable {
    func generateBriefing(
        input: FlowDirectorInput,
        scheduling: FlowSchedulingResult
    ) async throws -> FlowBriefingCopy
}
