import Foundation

/// Mutable accumulator updated by each scheduling rule during a pass.
public struct MutableSchedulingState: Sendable, Equatable {
    public var heroTask: LifeTask?
    public var actionType: FlowActionType
    public var suggestedDurationMinutes: Int
    public var rescheduledTasks: [RescheduleNotice]
    public var coachMoment: CoachMoment?
    public var flowWindow: DateInterval?
    public var nextCalendarEvent: CalendarEventReference?
    public var reasoningLines: [String]
    public var appliedRuleIDs: [String]
    public var maxDurationCap: Int?

    public init(
        heroTask: LifeTask? = nil,
        actionType: FlowActionType = .start,
        suggestedDurationMinutes: Int = 25,
        rescheduledTasks: [RescheduleNotice] = [],
        coachMoment: CoachMoment? = nil,
        flowWindow: DateInterval? = nil,
        nextCalendarEvent: CalendarEventReference? = nil,
        reasoningLines: [String] = [],
        appliedRuleIDs: [String] = [],
        maxDurationCap: Int? = nil
    ) {
        self.heroTask = heroTask
        self.actionType = actionType
        self.suggestedDurationMinutes = max(suggestedDurationMinutes, 1)
        self.rescheduledTasks = rescheduledTasks
        self.coachMoment = coachMoment
        self.flowWindow = flowWindow
        self.nextCalendarEvent = nextCalendarEvent
        self.reasoningLines = reasoningLines
        self.appliedRuleIDs = appliedRuleIDs
        self.maxDurationCap = maxDurationCap
    }

    /// Applies a duration cap if one was set by a rule.
    public mutating func clampDuration() {
        if let cap = maxDurationCap {
            suggestedDurationMinutes = min(suggestedDurationMinutes, cap)
        }
        suggestedDurationMinutes = max(suggestedDurationMinutes, TaskDurationPolicy.minimumMinutes)
    }
}
