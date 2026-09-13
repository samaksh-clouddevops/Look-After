import Foundation
import Combine
import LookAfterCore

/// Orchestrates environment fusion, behavior analysis, scheduling, briefing, and surface publishing.
///
/// Contains **no scheduling business logic** — delegates to injected engines and builders.
@MainActor
public final class FlowDirector: FlowDirectorProtocol, ObservableObject {

    @Published public private(set) var surface: FlowSurface = .empty
    @Published public private(set) var isOrchestrating: Bool = false

    public var session: FlowDirectorSession

    private let schedulingEngine: FlowSchedulingEngineProtocol
    private let confidenceEngine: FlowConfidenceEngineProtocol
    private let briefingProvider: FlowBriefingProviderProtocol
    private let behaviorStore: BehaviorMemoryStoreProtocol
    private let analysisEngine: BehaviorAnalysisEngineProtocol
    private let environmentSource: EnvironmentContextProviding
    private var lastEnvironmentContext: EnvironmentContext = .baseline

    /// Serializes concurrent orchestrate/complete/defer so older pipelines cannot overwrite a fresher surface.
    private var orchestrationTail: Task<Void, Never>?
    private var orchestrationGeneration: UInt64 = 0

    public init(
        session: FlowDirectorSession = FlowDirectorSession(),
        schedulingEngine: FlowSchedulingEngineProtocol = FlowSchedulingEngine(),
        confidenceEngine: FlowConfidenceEngineProtocol = FlowConfidenceEngine(),
        briefingProvider: FlowBriefingProviderProtocol = DeterministicFlowBriefingProvider(),
        behaviorStore: BehaviorMemoryStoreProtocol,
        analysisEngine: BehaviorAnalysisEngineProtocol,
        environmentSource: EnvironmentContextProviding
    ) {
        self.session = session
        self.schedulingEngine = schedulingEngine
        self.confidenceEngine = confidenceEngine
        self.briefingProvider = briefingProvider
        self.behaviorStore = behaviorStore
        self.analysisEngine = analysisEngine
        self.environmentSource = environmentSource
    }

    // MARK: - FlowDirectorProtocol

    public func orchestrate() async {
        await orchestrate(session: session)
    }

    public func handleTaskCompleted(_ task: LifeTask) async {
        let duration = task.actualMinutes ?? task.estimatedMinutes
        await behaviorStore.recordCompletion(
            task: task,
            durationMinutes: duration,
            context: lastEnvironmentContext
        )
        await orchestrate()
    }

    public func handleTaskDeferred(_ task: LifeTask) async {
        await behaviorStore.recordDeferral(task: task, context: lastEnvironmentContext)
        await orchestrate()
    }

    public func handleFlowSessionEnded(durationMinutes: Int) async {
        let hero = surface.heroTask
        await behaviorStore.recordFlowSession(
            task: hero,
            durationMinutes: durationMinutes,
            context: lastEnvironmentContext
        )
        session.activeFlowSession = nil
        await orchestrate()
    }

    // MARK: - Orchestration

    /// Full pipeline entry point — used by tests and app layer overrides.
    /// Concurrent callers join a serial chain; only the latest generation publishes `surface`.
    public func orchestrate(session: FlowDirectorSession) async {
        // Capture session snapshot so a mid-flight mutation of `self.session` cannot race this pass.
        let sessionSnapshot = session
        orchestrationGeneration &+= 1
        let generation = orchestrationGeneration

        let previous = orchestrationTail
        let task = Task { @MainActor in
            if let previous {
                await previous.value
            }
            guard generation == self.orchestrationGeneration else { return }
            await self.runOrchestrationPipeline(session: sessionSnapshot, generation: generation)
        }
        orchestrationTail = task
        await task.value
    }

    private func runOrchestrationPipeline(session: FlowDirectorSession, generation: UInt64) async {
        isOrchestrating = true
        defer {
            if generation == orchestrationGeneration {
                isOrchestrating = false
            }
        }

        let envResult = await environmentSource.currentContext(
            cognitiveSnapshot: session.cognitiveSnapshot,
            healthSummary: session.healthSummary,
            at: session.currentTime
        )
        guard generation == orchestrationGeneration else { return }
        lastEnvironmentContext = envResult.context

        let events = await behaviorStore.fetchEvents()
        guard generation == orchestrationGeneration else { return }
        let behavior = await analysisEngine.buildSnapshot(from: events)
        guard generation == orchestrationGeneration else { return }

        let input = FlowDirectorInput(
            cognitiveSnapshot: session.cognitiveSnapshot,
            healthSummary: session.healthSummary,
            pendingTasks: session.pendingTasks,
            recentProductivity: session.recentProductivity,
            calendarEvents: session.calendarEvents,
            behaviorMemory: behavior,
            environmentContext: envResult.context,
            activeFlowSession: session.activeFlowSession,
            currentTime: session.currentTime,
            userName: session.userName
        )

        let scheduling = schedulingEngine.schedule(from: input)
        let confidence = confidenceEngine.assess(
            FlowConfidenceInput(
                directorInput: input,
                scheduling: scheduling,
                signalAvailability: envResult.availability
            )
        )

        var enrichedScheduling = scheduling
        enrichedScheduling.confidence = confidence.overallScore

        let briefing = await fetchBriefing(input: input, scheduling: enrichedScheduling)
        guard generation == orchestrationGeneration else { return }

        surface = FlowSurfaceBuilder.build(from: FlowSurfaceBuildInput(
            scheduling: enrichedScheduling,
            briefing: briefing,
            behaviorMemory: behavior,
            environmentContext: envResult.context,
            confidence: confidence,
            worldPeek: session.worldPeek,
            generatedAt: session.currentTime
        ))
    }

    private func fetchBriefing(
        input: FlowDirectorInput,
        scheduling: FlowSchedulingResult
    ) async -> FlowBriefingCopy {
        do {
            return try await briefingProvider.generateBriefing(input: input, scheduling: scheduling)
        } catch {
            return FlowBriefingCopy()
        }
    }
}
