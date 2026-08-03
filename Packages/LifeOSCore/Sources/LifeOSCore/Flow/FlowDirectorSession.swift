import Foundation

/// Mutable session state the app layer updates between orchestration cycles.
public struct FlowDirectorSession: Sendable {
    public var cognitiveSnapshot: CognitiveSnapshot
    public var healthSummary: HealthSummary?
    public var pendingTasks: [LifeTask]
    public var recentProductivity: [ProductivitySession]
    public var calendarEvents: [CalendarEventReference]
    public var activeFlowSession: FlowSessionState?
    public var currentTime: Date
    public var userName: String
    public var worldPeek: FlowWorldPeek

    public init(
        cognitiveSnapshot: CognitiveSnapshot = CognitiveSnapshot(),
        healthSummary: HealthSummary? = nil,
        pendingTasks: [LifeTask] = [],
        recentProductivity: [ProductivitySession] = [],
        calendarEvents: [CalendarEventReference] = [],
        activeFlowSession: FlowSessionState? = nil,
        currentTime: Date = Date(),
        userName: String = "",
        worldPeek: FlowWorldPeek = .empty
    ) {
        self.cognitiveSnapshot = cognitiveSnapshot
        self.healthSummary = healthSummary
        self.pendingTasks = pendingTasks
        self.recentProductivity = recentProductivity
        self.calendarEvents = calendarEvents
        self.activeFlowSession = activeFlowSession
        self.currentTime = currentTime
        self.userName = userName
        self.worldPeek = worldPeek
    }
}
