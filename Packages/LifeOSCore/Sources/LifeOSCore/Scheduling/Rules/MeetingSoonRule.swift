import Foundation

/// Caps session length and prefers short tasks when a meeting starts within 45 minutes.
public struct MeetingSoonRule: FlowSchedulingRuleProtocol {
    public let meetingThresholdMinutes: Int
    public let maxSessionMinutes: Int

    public let identifier = "MeetingSoonRule"

    public init(meetingThresholdMinutes: Int = 45, maxSessionMinutes: Int = 30) {
        self.meetingThresholdMinutes = meetingThresholdMinutes
        self.maxSessionMinutes = maxSessionMinutes
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        guard let event = context.nextCalendarEvent else { return }
        guard event.minutesUntilStart >= 0, event.minutesUntilStart < meetingThresholdMinutes else { return }

        state.maxDurationCap = min(state.maxDurationCap ?? maxSessionMinutes, maxSessionMinutes)
        state.nextCalendarEvent = event

        if let hero = state.heroTask, FlowTaskSelector.effectiveMinutes(for: hero) > maxSessionMinutes {
            if let shorter = FlowTaskSelector.selectShortestSuitableTask(from: context, maxMinutes: maxSessionMinutes) {
                state.heroTask = shorter
                state.actionType = .startSmall
                state.reasoningLines.append("Meeting in \(event.minutesUntilStart) minutes — shorter task selected.")
            } else {
                state.reasoningLines.append("Meeting in \(event.minutesUntilStart) minutes — session capped at \(maxSessionMinutes) minutes.")
            }
        } else {
            state.reasoningLines.append("Meeting in \(event.minutesUntilStart) minutes — session capped at \(maxSessionMinutes) minutes.")
        }

        state.appliedRuleIDs.append(identifier)
    }
}
