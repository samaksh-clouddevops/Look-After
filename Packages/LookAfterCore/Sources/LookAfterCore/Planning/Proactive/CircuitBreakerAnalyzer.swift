import Foundation

/// Hyperfocus and overwhelm circuit breakers.
public enum CircuitBreakerAnalyzer {
    public static func analyze(
        focusSessionActive: Bool,
        focusSessionElapsedMinutes: Int,
        focusTaskTitle: String?,
        activeTaskCount: Int,
        behaviorMemory: BehaviorMemorySnapshot,
        capacityBand: ExecutiveCapacityBand?,
        now: Date = Date()
    ) -> [ProactiveAction] {
        var actions: [ProactiveAction] = []

        if focusSessionActive, focusSessionElapsedMinutes >= 90, let title = focusTaskTitle {
            let question = DaySupervisorContinuity.focusMismatchQuestion(kind: "hyperfocusBreak")
            actions.append(ProactiveAction(
                kind: .hyperfocusBreak,
                severity: .high,
                message: "You've been deep in \"\(title)\" for \(focusSessionElapsedMinutes)m — \(question.prompt)",
                options: question.options,
                surface: .banner,
                metadata: ["elapsed": "\(focusSessionElapsedMinutes)"]
            ))
        }

        let totalDeferrals = behaviorMemory.deferralRecords.reduce(0) { $0 + $1.deferralCount }
        let lowCapacity = capacityBand == .lowCapacity || capacityBand == .recoveryMode
        if activeTaskCount >= 8, totalDeferrals >= 5, lowCapacity {
            let question = DaySupervisorContinuity.focusMismatchQuestion(kind: "overwhelm")
            actions.append(ProactiveAction(
                kind: .overwhelmCircuitBreaker,
                severity: .high,
                message: question.prompt,
                options: question.options,
                surface: .banner,
                metadata: ["deferrals": "\(totalDeferrals)"]
            ))
        }

        return actions
    }
}
