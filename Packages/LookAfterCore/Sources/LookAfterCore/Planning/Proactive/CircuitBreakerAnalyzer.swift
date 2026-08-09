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
            actions.append(ProactiveAction(
                kind: .hyperfocusBreak,
                severity: .high,
                message: "You've been deep in \"\(title)\" for \(focusSessionElapsedMinutes)m — stretch + water?",
                options: ["Take a break", "Snooze 15m", "Mark done"],
                surface: .banner,
                metadata: ["elapsed": "\(focusSessionElapsedMinutes)"]
            ))
        }

        let totalDeferrals = behaviorMemory.deferralRecords.reduce(0) { $0 + $1.deferralCount }
        let lowCapacity = capacityBand == .lowCapacity || capacityBand == .recoveryMode
        if activeTaskCount >= 8, totalDeferrals >= 5, lowCapacity {
            actions.append(ProactiveAction(
                kind: .overwhelmCircuitBreaker,
                severity: .high,
                message: "Today's a lot — switch to emergency mode with your top 3?",
                options: ["Emergency mode", "Defer 3 tasks", "Keep plan"],
                surface: .banner,
                metadata: ["deferrals": "\(totalDeferrals)"]
            ))
        }

        return actions
    }
}
