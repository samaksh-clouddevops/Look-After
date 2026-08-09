import Foundation

// MARK: - Pre-window

public enum PreWindowAgent {
    public static func evaluate(
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProactiveAction] {
        guard let waiting = WaitingModeAnalyzer.analyze(tasks: tasks, now: now, calendar: calendar) else { return [] }
        return [WaitingModeAnalyzer.proactiveAction(from: waiting)]
    }
}

// MARK: - Post-completion

public enum PostCompletionAgent {
    public static func evaluate(
        completedTodayCount: Int,
        nextTask: LifeTask?,
        now: Date = Date()
    ) -> [ProactiveAction] {
        guard completedTodayCount >= 3, completedTodayCount % 3 == 0, let nextTask else { return [] }
        return [
            ProactiveAction(
                kind: .postCompletionMomentum,
                severity: .medium,
                message: "Nice streak — 5 min on \"\(nextTask.title)\" while you're rolling?",
                options: ["Start 5-min", "Pick another", "Not now"],
                surface: .notification,
                relatedTaskIDs: [nextTask.id],
                expiresAt: now.addingTimeInterval(20 * 60)
            )
        ]
    }
}

// MARK: - Stall

public enum StallAgent {
    public static func evaluate(
        foregroundCount: Int,
        completedTodayCount: Int,
        lastCompletionAt: Date?,
        now: Date = Date()
    ) -> [ProactiveAction] {
        guard foregroundCount >= 3 else { return [] }
        if let lastCompletionAt, now.timeIntervalSince(lastCompletionAt) < 2 * 3600 {
            return []
        }
        if completedTodayCount > 0, let lastCompletionAt, now.timeIntervalSince(lastCompletionAt) < 2 * 3600 {
            return []
        }
        return [
            ProactiveAction(
                kind: .initiationBridge,
                severity: .high,
                message: "You've opened the app a few times — want a 2-min micro-start?",
                options: ["Start 2-min", "Defer one thing", "Not now"],
                surface: .banner
            )
        ]
    }
}

// MARK: - Social debt

public enum SocialDebtAgent {
    public static func evaluate(
        emailActions: [ProactiveAction],
        relationshipActions: [ProactiveAction]
    ) -> [ProactiveAction] {
        guard let email = emailActions.first(where: { $0.kind == .emailActionRequired }),
              let drift = relationshipActions.first(where: { $0.kind == .relationshipDrift }) else {
            return []
        }
        let contact = drift.metadata["contactName"] ?? "someone"
        return [
            ProactiveAction(
                kind: .relationshipDrift,
                severity: .medium,
                message: "Email needs a reply and \(contact) is drifting — batch a 10-min social block?",
                options: ["Draft reply", "Schedule call", "Snooze"],
                surface: .banner,
                relatedInboxIDs: email.relatedInboxIDs,
                metadata: drift.metadata.merging(["emailThread": email.metadata["threadID"] ?? ""]) { $1 }
            )
        ]
    }
}

// MARK: - End of day

public enum EndOfDayAgent {
    public static func evaluate(
        tasks: [LifeTask],
        profile: UserLifeProfile,
        lifeModel: LifeModel?,
        referenceDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProactiveAction] {
        let dayStart = calendar.startOfDay(for: referenceDate)
        let boundaryContext = DayBoundaryPlanner.Context(profile: profile, tasks: tasks, lifeModel: lifeModel)
        let dayEnd = DayBoundaryPlanner.actionableDayEnd(on: dayStart, now: now, calendar: calendar, context: boundaryContext)
        let openToday = tasks.filter { task in
            task.status.isActive && TaskRecurrenceEngine.isActionableToday(task, in: tasks, calendar: calendar, referenceDate: referenceDate)
        }
        guard now >= dayEnd.addingTimeInterval(-45 * 60), openToday.count >= 2 else { return [] }
        return [
            ProactiveAction(
                kind: .endOfDayClose,
                severity: .medium,
                message: "\(openToday.count) tasks still open — reschedule, done, or let go?",
                options: ["Reschedule", "Mark done", "Defer to tomorrow"],
                surface: .banner,
                relatedTaskIDs: openToday.prefix(3).map(\.id)
            )
        ]
    }
}
