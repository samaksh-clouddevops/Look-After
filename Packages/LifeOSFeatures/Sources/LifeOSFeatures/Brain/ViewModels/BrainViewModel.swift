import Foundation
import LifeOSCore
import LifeOSAI
import LifeOSData

/// View-layer adapter: fetches repos, orchestrates via FlowDirector or legacy ExecutiveBrain.
@MainActor
public final class BrainViewModel: ObservableObject {

    @Published public var recommendation: String = ""
    @Published public var cognitiveSnapshot: CognitiveSnapshot?
    @Published public var isLoading: Bool = false
    @Published public var error: String?
    @Published public var topTasks: [LifeTask] = []
    @Published public var healthSummary: HealthSummary?
    @Published public private(set) var presentation: BrainPresentation = .empty

    /// Latest orchestrated surface when Flow Director is enabled.
    @Published public private(set) var flowSurface: FlowSurface?

    /// Whether the last refresh used Flow Director scheduling.
    @Published public private(set) var isUsingFlowDirector: Bool = false

    /// Duration of the last Flow Director orchestration pass (ms). Zero when legacy path used.
    @Published public private(set) var lastOrchestrationDurationMs: Double = 0

    private let brain: ExecutiveBrain
    private let cognitiveModel: CognitiveModel
    private let taskRepo: TaskRepository
    private let healthRepo: HealthSummaryRepository
    private let energyRepo: EnergyReportRepository
    private var flowDirector: FlowDirector?

    public init(
        brain: ExecutiveBrain,
        flowDirector: FlowDirector? = nil,
        cognitiveModel: CognitiveModel = CognitiveModel(),
        taskRepo: TaskRepository? = nil,
        healthRepo: HealthSummaryRepository? = nil,
        energyRepo: EnergyReportRepository? = nil
    ) {
        self.brain = brain
        self.flowDirector = flowDirector
        self.cognitiveModel = cognitiveModel
        self.taskRepo = taskRepo ?? TaskRepository()
        self.healthRepo = healthRepo ?? HealthSummaryRepository()
        self.energyRepo = energyRepo ?? EnergyReportRepository()
    }

    /// Attach or replace the Flow Director instance (async factory wiring from app layer).
    public func configure(flowDirector: FlowDirector) {
        self.flowDirector = flowDirector
    }

    /// Builds structured Brain tab presentation from orchestrator output.
    public func syncFromOrchestrator(
        heroBriefing: HeroBriefing?,
        resumeSnapshot: ResumeSnapshot?,
        executiveCapacity: ExecutiveCapacityState,
        lifeSnapshot: LifeContextSnapshot?,
        activeTasks: [LifeTask],
        upcomingBills: [BillItem],
        medications: [Medication],
        timelineItems: [LifeTimelineEvent],
        readinessLabel: String? = nil
    ) {
        presentation = BrainPresentationBuilder.build(
            heroBriefing: heroBriefing,
            resumeSnapshot: resumeSnapshot,
            executiveCapacity: executiveCapacity,
            lifeSnapshot: lifeSnapshot,
            flowSurface: flowSurface,
            cognitiveSnapshot: cognitiveSnapshot,
            healthSummary: healthSummary,
            activeTasks: activeTasks,
            upcomingBills: upcomingBills,
            medications: medications,
            timelineItems: timelineItems,
            readinessLabel: readinessLabel
        )
    }

    /// Persists a self-reported energy check-in and refreshes the cognitive snapshot inputs.
    public func logEnergyReport(energy: EnergyLevel, focusNote: String?, userId: String) async {
        let report = EnergyReport(
            energy: energy,
            mood: focusNote,
            notes: focusNote,
            userId: userId
        )
        do {
            try await energyRepo.save(report)
            await refresh(userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Load all data and produce recommendation via Flow Director or legacy ExecutiveBrain.
    public func refresh(
        userId: String,
        activeFlowSession: FlowSessionState? = nil
    ) async {
        isLoading = true
        error = nil

        do {
            async let tasks = taskRepo.getActive(for: userId)
            async let completed = taskRepo.getCompletedToday(for: userId)
            async let health = healthRepo.getLatest(for: userId)
            async let energyReports = energyRepo.getToday(for: userId)

            let activeTasks = try await tasks
            let completedTasks = try await completed
            let latestHealth = try await health
            let todaysEnergy = try await energyReports

            self.healthSummary = latestHealth

            let userName = UserDefaults.standard.string(forKey: "userName") ?? "User"
            let profile = UserLifeProfileStore.loadUserProfile(displayName: userName)
            let snapshot = cognitiveModel.generateSnapshot(
                healthSummary: latestHealth,
                recentEnergyReports: todaysEnergy,
                completedTasksToday: completedTasks,
                profile: profile
            )
            self.cognitiveSnapshot = snapshot

            if FlowDirectorFeature.isEnabled, let director = flowDirector {
                await refreshViaFlowDirector(
                    director: director,
                    snapshot: snapshot,
                    health: latestHealth,
                    activeTasks: activeTasks,
                    activeFlowSession: activeFlowSession,
                    userId: userId
                )
            } else {
                await refreshViaExecutiveBrain(
                    snapshot: snapshot,
                    health: latestHealth,
                    activeTasks: activeTasks
                )
            }

        } catch {
            self.error = error.localizedDescription
            self.recommendation = "Pick one small task and start there."
            self.topTasks = []
            self.flowSurface = nil
            self.isUsingFlowDirector = false
        }

        isLoading = false
    }

    public func handleTaskCompleted(_ task: LifeTask, userId: String, activeFlowSession: FlowSessionState? = nil) async {
        guard FlowDirectorFeature.isEnabled, let director = flowDirector else { return }
        await director.handleTaskCompleted(task)
        await refresh(userId: userId, activeFlowSession: activeFlowSession)
    }

    public func handleTaskDeferred(_ task: LifeTask, userId: String, activeFlowSession: FlowSessionState? = nil) async {
        guard FlowDirectorFeature.isEnabled, let director = flowDirector else { return }
        await director.handleTaskDeferred(task)
        await refresh(userId: userId, activeFlowSession: activeFlowSession)
    }

    public func handleFlowSessionEnded(durationMinutes: Int, userId: String, activeFlowSession: FlowSessionState? = nil) async {
        guard FlowDirectorFeature.isEnabled, let director = flowDirector else { return }
        await director.handleFlowSessionEnded(durationMinutes: durationMinutes)
        await refresh(userId: userId, activeFlowSession: activeFlowSession)
    }

    // MARK: - Private

    private func refreshViaExecutiveBrain(
        snapshot: CognitiveSnapshot,
        health: HealthSummary?,
        activeTasks: [LifeTask]
    ) async {
        isUsingFlowDirector = false
        flowSurface = nil
        lastOrchestrationDurationMs = 0
        topTasks = Array(activeTasks.prefix(5))

        if let hero = topTasks.first {
            let semantics = SemanticDecisionBuilder.from(
                task: hero,
                healthSummary: health
            )
            recommendation = HumanLanguage.recommendationSummary(from: semantics)
        } else {
            recommendation = HumanLanguage.defaultWhyNow()
        }
    }

    private func refreshViaFlowDirector(
        director: FlowDirector,
        snapshot: CognitiveSnapshot,
        health: HealthSummary?,
        activeTasks: [LifeTask],
        activeFlowSession: FlowSessionState?,
        userId: String
    ) async {
        isUsingFlowDirector = true
        lastOrchestrationDurationMs = 0
        let userName = UserDefaults.standard.string(forKey: "userName") ?? ""

        director.session = FlowDirectorSession(
            cognitiveSnapshot: snapshot,
            healthSummary: health,
            pendingTasks: activeTasks,
            activeFlowSession: activeFlowSession,
            currentTime: Date(),
            userName: userName
        )

        let start = Date()
        await director.orchestrate()
        lastOrchestrationDurationMs = Date().timeIntervalSince(start) * 1000

        applyFlowSurface(director.surface, activeTasks: activeTasks)
    }

    private func applyFlowSurface(_ surface: FlowSurface, activeTasks: [LifeTask]) {
        flowSurface = surface

        var lines = [String]()
        if !surface.greeting.isEmpty { lines.append(surface.greeting) }
        lines.append(contentsOf: surface.briefingLines)
        if let prediction = surface.prediction, !prediction.reasoning.isEmpty {
            lines.append(prediction.reasoning)
        }
        recommendation = UserFacingCopy.sanitize(lines.filter { !$0.isEmpty }.joined(separator: "\n"))

        if let hero = surface.heroTask {
            var ordered = activeTasks
            if let index = ordered.firstIndex(where: { $0.id == hero.id }) {
                let item = ordered.remove(at: index)
                ordered.insert(item, at: 0)
            } else {
                ordered.insert(hero, at: 0)
            }
            topTasks = Array(ordered.prefix(5))
        } else {
            topTasks = Array(activeTasks.prefix(5))
        }
    }

    #if DEBUG
    public func setFlowSurfaceForTesting(_ surface: FlowSurface?) {
        self.flowSurface = surface
    }
    #endif

    /// Clears all cached brain presentation state after factory reset.
    public func resetForFactoryReset() {
        recommendation = ""
        cognitiveSnapshot = nil
        healthSummary = nil
        topTasks = []
        flowSurface = nil
        presentation = .empty
        isUsingFlowDirector = false
        lastOrchestrationDurationMs = 0
        error = nil
        isLoading = false
        brain.resetForFactoryReset()
    }
}
