import Foundation

/// Weekly scan for chronic deferrals — shrink, kill, or peak-window schedule.
public enum DeferralRecoveryWeeklyAgent {
    public static func evaluate(
        deferralRecords: [TaskDeferralRecord],
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProactiveAction? {
        guard calendar.component(.weekday, from: now) == 2 else { return nil }
        let chronic = deferralRecords.filter { $0.deferralCount >= 3 }
        guard let worst = chronic.max(by: { $0.deferralCount < $1.deferralCount }),
              let task = tasks.first(where: { $0.id == worst.taskID }) else { return nil }

        return ProactiveAction(
            kind: .deferralRecovery,
            severity: .medium,
            message: "\"\(task.title)\" deferred \(worst.deferralCount)× — shrink it, drop it, or schedule in peak window?",
            options: ["Shrink to 5 min", "Remove task", "Peak window"],
            surface: .banner,
            relatedTaskIDs: [task.id],
            metadata: ["deferralCount": "\(worst.deferralCount)"]
        )
    }
}
