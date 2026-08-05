import Foundation
import LookAfterCore
import LookAfterData
import LookAfterAI
import ExecutiveBrain

/// Runs the Executive Brain continuously and publishes BrainState for UI rendering.
@MainActor
public final class ContextOrchestrator: ObservableObject {
    @Published public private(set) var snapshot: LifeContextSnapshot?
    @Published public private(set) var briefing: ContextBriefing?
    @Published public private(set) var brainState: BrainState?
    @Published public private(set) var executiveCapacity: ExecutiveCapacityState = .moderate
    @Published public private(set) var resumeSnapshot: ResumeSnapshot?
    @Published public private(set) var lifeTimelineEvents: [LifeTimelineEvent] = []
    @Published public private(set) var tomorrowLifeTimelineEvents: [LifeTimelineEvent] = []
    @Published public private(set) var decisionHistory: [DecisionRecord] = []

    private let contextEngine = ContextEngine()
    private let executiveBrain = ExecutiveBrainEngine()
    private let capacityEngine: ExecutiveCapacityEngine
    private let historyStore = DecisionHistoryStore.shared
    private let environmentProvider: EnvironmentContextProvider
    private let resumeEngine: ResumeEngine
    private var userId: String = ""

    public init(
        environmentProvider: EnvironmentContextProvider = EnvironmentContextProvider(
            calendarProvider: EventKitCalendarEnvironmentSignalProvider()
        ),
        resumeEngine: ResumeEngine = .shared,
        glmService: GLMService? = nil
    ) {
        self.environmentProvider = environmentProvider
        self.resumeEngine = resumeEngine
        self.capacityEngine = ExecutiveCapacityEngine(glmService: glmService)
    }

    public struct RefreshInput: Sendable {
        public var userId: String
        public var userName: String
        public var cognitiveSnapshot: CognitiveSnapshot?
        public var healthSummary: HealthSummary?
        public var flowSurface: FlowSurface?
        public var activeFlowSession: FlowSessionState?
        public var heroTask: LifeTask?
        public var topTasks: [LifeTask]
        public var unpurchasedShoppingCount: Int
        public var upcomingBills: [BillItem]
        public var lifeTimelineEvents: [LifeTimelineEvent]
        public var tomorrowLifeTimelineEvents: [LifeTimelineEvent]
        public var isWeekend: Bool
        public var peakStartHour: Int
        public var locationOverride: LocationContext?
        public var allTasks: [LifeTask]
        public var completedTaskIDs: Set<String>
        public var flowConfidenceScore: Double?
        public var capacityLLMPolicy: ExecutiveCapacityLLMPolicy

        public init(
            userId: String,
            userName: String,
            cognitiveSnapshot: CognitiveSnapshot?,
            healthSummary: HealthSummary?,
            flowSurface: FlowSurface?,
            activeFlowSession: FlowSessionState?,
            heroTask: LifeTask?,
            topTasks: [LifeTask],
            unpurchasedShoppingCount: Int,
            upcomingBills: [BillItem] = [],
            lifeTimelineEvents: [LifeTimelineEvent] = [],
            tomorrowLifeTimelineEvents: [LifeTimelineEvent] = [],
            isWeekend: Bool = false,
            peakStartHour: Int = 9,
            locationOverride: LocationContext? = nil,
            allTasks: [LifeTask] = [],
            completedTaskIDs: Set<String> = [],
            flowConfidenceScore: Double? = nil,
            capacityLLMPolicy: ExecutiveCapacityLLMPolicy = .deterministicOnly
        ) {
            self.userId = userId
            self.userName = userName
            self.cognitiveSnapshot = cognitiveSnapshot
            self.healthSummary = healthSummary
            self.flowSurface = flowSurface
            self.activeFlowSession = activeFlowSession
            self.heroTask = heroTask
            self.topTasks = topTasks
            self.unpurchasedShoppingCount = unpurchasedShoppingCount
            self.upcomingBills = upcomingBills
            self.lifeTimelineEvents = lifeTimelineEvents
            self.tomorrowLifeTimelineEvents = tomorrowLifeTimelineEvents
            self.isWeekend = isWeekend
            self.peakStartHour = peakStartHour
            self.locationOverride = locationOverride
            self.allTasks = allTasks
            self.completedTaskIDs = completedTaskIDs
            self.flowConfidenceScore = flowConfidenceScore
            self.capacityLLMPolicy = capacityLLMPolicy
        }
    }

    public func refresh(_ input: RefreshInput) async {
        let userId = input.userId
        let userName = input.userName
        let cognitiveSnapshot = input.cognitiveSnapshot
        let healthSummary = input.healthSummary
        let flowSurface = input.flowSurface
        let activeFlowSession = input.activeFlowSession
        let heroTask = input.heroTask
        let topTasks = input.topTasks
        let unpurchasedShoppingCount = input.unpurchasedShoppingCount
        let upcomingBills = input.upcomingBills
        let lifeTimelineEvents = input.lifeTimelineEvents
        let tomorrowLifeTimelineEvents = input.tomorrowLifeTimelineEvents
        let isWeekend = input.isWeekend
        let peakStartHour = input.peakStartHour
        let locationOverride = input.locationOverride
        let allTasks = input.allTasks
        let completedTaskIDs = input.completedTaskIDs
        let flowConfidenceScore = input.flowConfidenceScore
        let capacityLLMPolicy = input.capacityLLMPolicy
        // Performance optimization: Compute all values first, then batch update @Published properties
        // This reduces SwiftUI re-renders from 7 separate updates to 1 batched update
        await PerformanceMonitor.measureAsync("ContextOrchestrator.refresh", warnAfterMs: 200) {
            self.userId = userId
            let resumeSnap = resumeEngine.load(userId: userId)

            let envResult = await environmentProvider.currentContext(
                cognitiveSnapshot: cognitiveSnapshot ?? CognitiveSnapshot(),
                healthSummary: healthSummary,
                at: Date()
            )

            var environment = envResult.context
            if let locationOverride { environment.locationContext = locationOverride }

            let input = ContextEngineInput(
                cognitiveSnapshot: cognitiveSnapshot,
                healthSummary: healthSummary,
                environment: environment,
                flowSurface: flowSurface,
                activeFlowSession: activeFlowSession,
                heroTask: heroTask,
                topTasks: topTasks,
                unpurchasedShoppingCount: unpurchasedShoppingCount,
                resumeSnapshot: resumeSnap,
                peakStartHour: peakStartHour
            )

            let calculated = contextEngine.calculate(input)

            let medications = MedicationStore.load()
            let tasks = allTasks.isEmpty ? topTasks : allTasks

            let tickInput = BrainTickInput(
                snapshot: calculated,
                cognitiveSnapshot: cognitiveSnapshot,
                healthSummary: healthSummary,
                resume: resumeSnap,
                medications: medications,
                tasks: tasks,
                timelineItems: lifeTimelineEvents,
                upcomingBills: upcomingBills,
                userName: userName,
                isWeekend: isWeekend,
                peakStartHour: peakStartHour,
                completedTaskIDs: completedTaskIDs,
                flowConfidenceScore: flowConfidenceScore
            )

            let state = executiveBrain.tick(tickInput)
            let history = historyStore.recent(limit: 30)

            let meetingCount = lifeTimelineEvents.filter { $0.kind == .meeting }.count
            let capacityInput = ExecutiveCapacityInput(
                snapshot: calculated,
                healthSummary: healthSummary,
                cognitiveSnapshot: cognitiveSnapshot,
                completedTodayCount: completedTaskIDs.count,
                activeTaskCount: tasks.filter { $0.status.isActive }.count,
                meetingCountHint: meetingCount,
                isInFlowSession: activeFlowSession?.isActive == true,
                now: Date()
            )
            let capacity = await capacityEngine.evaluate(capacityInput, llmPolicy: capacityLLMPolicy)

            // Batch update all @Published properties - SwiftUI re-renders only ONCE
            snapshot = calculated
            resumeSnapshot = resumeSnap
            brainState = state
            briefing = state.briefing
            decisionHistory = history
            executiveCapacity = capacity
            self.lifeTimelineEvents = lifeTimelineEvents
            self.tomorrowLifeTimelineEvents = tomorrowLifeTimelineEvents
        }
    }

    /// Clears orchestrator output so UI cannot show stale brain/timeline state.
    public func resetInMemoryState() {
        snapshot = nil
        briefing = nil
        brainState = nil
        executiveCapacity = .moderate
        lifeTimelineEvents = []
        tomorrowLifeTimelineEvents = []
        decisionHistory = []
        resumeSnapshot = nil
    }

    public func recordDecisionAccepted() {
        guard let id = brainState?.decision.intent.id else { return }
        historyStore.recordAccepted(recordID: matchingRecordID(for: id))
        decisionHistory = historyStore.recent(limit: 30)
    }

    public func recordDecisionIgnored(reason: String?) {
        guard let id = brainState?.decision.intent.id else { return }
        historyStore.recordIgnored(recordID: matchingRecordID(for: id), reason: reason)
        decisionHistory = historyStore.recent(limit: 30)
    }

    public func recordDecisionCompleted(actualMinutes: Int) {
        guard let id = brainState?.decision.intent.id else { return }
        historyStore.recordCompleted(recordID: matchingRecordID(for: id), actualMinutes: actualMinutes)
        decisionHistory = historyStore.recent(limit: 30)
    }

    private func matchingRecordID(for intentID: String) -> String {
        historyStore.recent(limit: 5).first { $0.intent.id == intentID }?.id ?? intentID
    }

    // MARK: - Resume capture (forwarding)

    public func persistResume(
        userId: String,
        screen: String,
        experienceMode: ExperienceMode?,
        activeTask: LifeTask?,
        focusSession: FlowSessionState?,
        aiPreview: String?
    ) {
        resumeEngine.captureScreen(screen, userId: userId, experienceMode: experienceMode)
        if let task = activeTask {
            if focusSession?.isActive == true {
                resumeEngine.captureFocusSession(
                    task: task,
                    elapsedSeconds: focusSession?.elapsedSeconds ?? 0,
                    userId: userId
                )
            } else {
                resumeEngine.captureTask(task, screen: screen, userId: userId)
            }
        }
        if let preview = aiPreview {
            resumeEngine.captureAIConversation(preview, userId: userId)
        }
        resumeSnapshot = resumeEngine.load(userId: userId)
    }

    public func captureNote(_ text: String, userId: String) {
        resumeEngine.captureNote(text, userId: userId)
        resumeSnapshot = resumeEngine.load(userId: userId)
    }
}
