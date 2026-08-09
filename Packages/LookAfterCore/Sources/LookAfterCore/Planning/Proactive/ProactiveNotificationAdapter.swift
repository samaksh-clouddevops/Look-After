import Foundation

/// Converts proactive actions into notification candidates.
public enum ProactiveNotificationAdapter {
    public static func candidates(
        from actions: [ProactiveAction],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [NotificationCandidate] {
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        return actions.compactMap { action in
            guard action.surface == .notification else { return nil }
            guard action.expiresAt == nil || action.expiresAt! > now else { return nil }

            let kind: NotificationKind
            let route: NotificationRoute
            switch action.kind {
            case .transitionShield:
                kind = .transitionShield
                route = .today
            case .waitingMode:
                kind = .waitingMode
                route = .today
            case .patternCoach:
                kind = .patternInsight
                route = .briefing
            case .initiationBridge:
                kind = .initiationBridge
                route = .focusSession
            case .hyperfocusBreak:
                kind = .focusBreak
                route = .focusSession
            case .badDay where action.metadata["wakeRecovery"] == "true":
                kind = .wakeRecovery
                route = .today
            case .weekPrimer:
                kind = .weekPrimer
                route = .today
            case .endOfDayClose:
                kind = .endOfDayClose
                route = .today
            case .postCompletionMomentum:
                kind = .postCompletionMomentum
                route = .focusSession
            default:
                kind = .brainHero
                route = .today
            }

            let fireDate = resolvedFireDate(for: action, now: now) ?? now.addingTimeInterval(60)
            guard fireDate > now else { return nil }

            let anchorID = action.relatedTaskIDs.first
            let tierSuffix = action.metadata["tier"] ?? "0"
            return NotificationCandidate(
                id: NotificationIdentifier.proactive(kind, suffix: "\(anchorID ?? action.id).\(tierSuffix).\(dayKey)"),
                kind: kind,
                title: notificationTitle(for: action),
                body: action.message,
                fireDate: fireDate,
                route: route,
                routePayload: action.relatedTaskIDs.first ?? action.relatedInboxIDs.first,
                proactiveKind: action.kind.rawValue,
                anchorEventID: anchorID
            )
        }
    }

    private static func resolvedFireDate(for action: ProactiveAction, now: Date) -> Date? {
        if let iso = action.metadata["fireDate"],
           let date = FlexibleISO8601Date.date(from: iso) {
            return date
        }
        if let expiresAt = action.expiresAt {
            return min(expiresAt, now.addingTimeInterval(3600))
        }
        return nil
    }

    private static func notificationTitle(for action: ProactiveAction) -> String {
        switch action.kind {
        case .transitionShield: return "Transition soon"
        case .waitingMode: return "Quick win window"
        case .patternCoach: return "Pattern check-in"
        case .initiationBridge: return "Micro-start"
        case .hyperfocusBreak: return "Break time"
        case .badDay: return "Wake recovery"
        case .weekPrimer: return "Week ahead"
        case .endOfDayClose: return "Wind down"
        case .postCompletionMomentum: return "Keep rolling"
        default: return "Look After"
        }
    }
}
