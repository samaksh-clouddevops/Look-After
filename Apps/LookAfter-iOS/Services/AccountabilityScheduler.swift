import Foundation
import LookAfterCore

/// Schedules optional accountability nudge when initiation bridge fires.
enum AccountabilityScheduler {
    static func scheduleIfEnabled(for action: ProactiveAction, now: Date = Date()) {
        guard action.kind == .initiationBridge || action.kind == .accountabilityStart else { return }
        guard UserDefaults.standard.bool(forKey: "lookafter.accountability.enabled") else { return }
        let buddy = UserDefaults.standard.string(forKey: AccountabilitySettings.contactNameKey) ?? "buddy"
        let fireDate = now.addingTimeInterval(2 * 60)
        let candidate = NotificationCandidate(
            id: NotificationIdentifier.proactive(.initiationBridge, suffix: "accountability.\(action.id)"),
            kind: .initiationBridge,
            title: "Accountability check",
            body: "Ping \(buddy)? Your micro-start window is open.",
            fireDate: fireDate,
            route: .today,
            proactiveKind: ProactiveAction.Kind.bodyDoubleReminder.rawValue
        )
        Task {
            await NotificationScheduler.shared.scheduleSnooze(for: candidate, fireDate: fireDate)
        }
    }
}
