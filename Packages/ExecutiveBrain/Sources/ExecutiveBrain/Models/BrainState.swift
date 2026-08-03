import Foundation
import LookAfterCore

/// Everything the UI needs to render — no business logic in views.
public struct BrainState: Codable, Sendable, Equatable {
    public var world: WorldState
    public var decision: BrainDecision
    public var plan: DayPlan
    public var briefing: ContextBriefing
    public var snapshot: LifeContextSnapshot
    public var generatedAt: Date

    public init(
        world: WorldState,
        decision: BrainDecision,
        plan: DayPlan,
        briefing: ContextBriefing,
        snapshot: LifeContextSnapshot,
        generatedAt: Date = Date()
    ) {
        self.world = world
        self.decision = decision
        self.plan = plan
        self.briefing = briefing
        self.snapshot = snapshot
        self.generatedAt = generatedAt
    }

    /// Convenience — hero the UI already binds to.
    public var hero: HeroBriefing { briefing.hero }
}

/// All signals fed into one Brain tick.
public struct BrainTickInput: Sendable {
    public var snapshot: LifeContextSnapshot
    public var cognitiveSnapshot: CognitiveSnapshot?
    public var healthSummary: HealthSummary?
    public var resume: ResumeSnapshot?
    public var medications: [Medication]
    public var tasks: [LifeTask]
    public var timelineItems: [LifeTimelineEvent]
    public var upcomingBills: [BillItem]
    public var userName: String
    public var isWeekend: Bool
    public var peakStartHour: Int
    public var completedTaskIDs: Set<String>
    public var flowConfidenceScore: Double?
    public var now: Date

    public init(
        snapshot: LifeContextSnapshot,
        cognitiveSnapshot: CognitiveSnapshot? = nil,
        healthSummary: HealthSummary? = nil,
        resume: ResumeSnapshot? = nil,
        medications: [Medication] = [],
        tasks: [LifeTask] = [],
        timelineItems: [LifeTimelineEvent] = [],
        upcomingBills: [BillItem] = [],
        userName: String = "",
        isWeekend: Bool = false,
        peakStartHour: Int = 9,
        completedTaskIDs: Set<String> = [],
        flowConfidenceScore: Double? = nil,
        now: Date = Date()
    ) {
        self.snapshot = snapshot
        self.cognitiveSnapshot = cognitiveSnapshot
        self.healthSummary = healthSummary
        self.resume = resume
        self.medications = medications
        self.tasks = tasks
        self.timelineItems = timelineItems
        self.upcomingBills = upcomingBills
        self.userName = userName
        self.isWeekend = isWeekend
        self.peakStartHour = peakStartHour
        self.completedTaskIDs = completedTaskIDs
        self.flowConfidenceScore = flowConfidenceScore
        self.now = now
    }
}
