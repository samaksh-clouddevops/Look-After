import Foundation

/// Aggregated input for a single Flow Director orchestration cycle.
/// Assembled by the app layer from repositories, health sync, and session state.
public struct FlowDirectorInput: Codable, Sendable {
    public var cognitiveSnapshot: CognitiveSnapshot
    public var healthSummary: HealthSummary?
    public var pendingTasks: [LifeTask]
    public var recentProductivity: [ProductivitySession]
    public var calendarEvents: [CalendarEventReference]
    public var behaviorMemory: BehaviorMemorySnapshot
    public var environmentContext: EnvironmentContext
    public var activeFlowSession: FlowSessionState?
    public var currentTime: Date
    public var userName: String

    public init(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary? = nil,
        pendingTasks: [LifeTask] = [],
        recentProductivity: [ProductivitySession] = [],
        calendarEvents: [CalendarEventReference] = [],
        behaviorMemory: BehaviorMemorySnapshot = .empty,
        environmentContext: EnvironmentContext = .baseline,
        activeFlowSession: FlowSessionState? = nil,
        currentTime: Date = Date(),
        userName: String = ""
    ) {
        self.cognitiveSnapshot = cognitiveSnapshot
        self.healthSummary = healthSummary
        self.pendingTasks = pendingTasks
        self.recentProductivity = recentProductivity
        self.calendarEvents = calendarEvents
        self.behaviorMemory = behaviorMemory
        self.environmentContext = environmentContext
        self.activeFlowSession = activeFlowSession
        self.currentTime = currentTime
        self.userName = userName
    }
}
