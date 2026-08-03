import Foundation

/// Propagates calendar gap metadata (flow window, next event) into the scheduling result.
public struct CalendarGapRule: FlowSchedulingRuleProtocol {
    public let minGapMinutes: Int

    public let identifier = "CalendarGapRule"

    public init(minGapMinutes: Int = 90) {
        self.minGapMinutes = minGapMinutes
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        if let window = context.flowWindow {
            state.flowWindow = window
        } else if context.freeBlockMinutes >= minGapMinutes, let hero = state.heroTask {
            let start = context.currentTime
            let end = start.addingTimeInterval(TimeInterval(context.freeBlockMinutes * 60))
            state.flowWindow = DateInterval(start: start, end: end)
            state.reasoningLines.append("Calendar gap of \(context.freeBlockMinutes) minutes labeled as Flow Window.")
            _ = hero
        }

        if state.nextCalendarEvent == nil {
            state.nextCalendarEvent = context.nextCalendarEvent
        }

        if state.flowWindow != nil || state.nextCalendarEvent != nil {
            state.appliedRuleIDs.append(identifier)
        }
    }
}
