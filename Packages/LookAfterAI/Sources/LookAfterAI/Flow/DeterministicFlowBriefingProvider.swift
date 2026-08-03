import Foundation
import LookAfterCore

/// Deterministic briefing copy until D2.5 wires ExecutiveBrain / LLM.
public struct DeterministicFlowBriefingProvider: FlowBriefingProviderProtocol {

    public init() {}

    public func generateBriefing(
        input: FlowDirectorInput,
        scheduling: FlowSchedulingResult
    ) async throws -> FlowBriefingCopy {
        let name = input.userName.isEmpty ? "there" : input.userName
        let timeGreeting = greeting(for: input.environmentContext.timeOfDay)
        var lines: [String] = []

        if let event = scheduling.nextCalendarEvent {
            lines.append("\(event.title) starts in \(event.minutesUntilStart) minutes.")
        }

        if !scheduling.rescheduledTasks.isEmpty {
            for notice in scheduling.rescheduledTasks.prefix(2) {
                lines.append(notice.explanation)
            }
        }

        if let prediction = scheduling.prediction {
            lines.append(prediction.reasoning)
        }

        return FlowBriefingCopy(
            greeting: "\(timeGreeting), \(name).",
            briefingLines: Array(lines.prefix(3))
        )
    }

    private func greeting(for timeOfDay: TimeOfDay) -> String {
        switch timeOfDay {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Good night"
        }
    }
}
