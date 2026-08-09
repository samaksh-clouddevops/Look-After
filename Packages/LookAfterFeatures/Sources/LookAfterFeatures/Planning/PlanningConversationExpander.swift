import Foundation
import LookAfterCore

/// Resolves short confirmations ("yes, add it") into actionable planning requests using prior turns.
public enum PlanningConversationExpander {

    public static func effectiveMessage(
        _ message: String,
        history: [PlanningConversationTurn]
    ) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConfirmation(trimmed) else { return message }

        if let priorUser = history.last(where: { $0.role == .user })?.text,
           !priorUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if PlanningReasoningPipeline.classify(priorUser) == .reschedule
                || isRescheduleContext(priorUser) {
                return "Please reschedule as we discussed: \(priorUser)"
            }
            return "Please create and schedule this on my timeline: \(priorUser)"
        }

        if let priorAssistant = history.last(where: { $0.role == .assistant })?.text,
           !priorAssistant.isEmpty {
            if isRescheduleContext(priorAssistant) {
                return "Yes — please reschedule as we just discussed: \(priorAssistant)"
            }
            return "Yes — please create and schedule what we just discussed: \(priorAssistant)"
        }

        return message
    }

    public static func isConfirmation(_ message: String) -> Bool {
        let lower = message
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "!.?"))
        guard !lower.isEmpty else { return false }

        let exact = [
            "yes", "yeah", "yep", "yup", "sure", "ok", "okay",
            "do it", "add it", "create it", "schedule it", "go ahead",
            "sounds good", "that works", "please do", "please add it",
            "add that", "create that", "schedule that", "make it happen"
        ]
        if exact.contains(lower) { return true }

        let prefixes = [
            "yes ", "yeah ", "sure ", "ok ", "okay ", "please create",
            "please add", "please schedule", "go ahead and"
        ]
        return prefixes.contains { lower.hasPrefix($0) }
    }

    /// Whether a free-form message should use the Executive Planning engine (task creation / schedule changes).
    public static func shouldUsePlanningEngine(for message: String) -> Bool {
        let lower = message.lowercased()
        let planningSignals = [
            "create", "add ", "schedule", "plan ", "put ", "block ",
            "move ", "reschedule", "defer", "postpone", "remind me",
            "i need to", "i have to", "today i", "tomorrow i",
            "fit in", "make time", "slot for", "task for"
        ]
        if planningSignals.contains(where: { lower.contains($0) }) { return true }
        if isConfirmation(message) { return true }
        return PlanningReasoningPipeline.classify(message) == .task
            || PlanningReasoningPipeline.classify(message) == .appointment
            || PlanningReasoningPipeline.classify(message) == .reminder
            || PlanningReasoningPipeline.classify(message) == .reschedule
    }

    private static func isRescheduleContext(_ text: String) -> Bool {
        PlanningReasoningPipeline.classify(text) == .reschedule
    }
}
