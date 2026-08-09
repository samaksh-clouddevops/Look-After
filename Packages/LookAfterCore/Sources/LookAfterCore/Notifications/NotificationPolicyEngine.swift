import Foundation

/// Selects proactive notifications under the daily cap and priority ranking.
public enum NotificationPolicyEngine {

    public struct SelectionResult: Sendable, Equatable {
        public var selected: [NotificationCandidate]
        public var droppedProactiveCount: Int

        public init(selected: [NotificationCandidate], droppedProactiveCount: Int = 0) {
            self.selected = selected
            self.droppedProactiveCount = droppedProactiveCount
        }
    }

    public static func select(
        candidates: [NotificationCandidate],
        preferences: NotificationPreferences,
        budget: ProactiveDailyBudget,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SelectionResult {
        let eligible = candidates.filter { candidate in
            guard candidate.fireDate > now else { return false }
            guard preferences.isEnabled(candidate.kind) else { return false }
            if budget.dismissedCandidateIDs.contains(candidate.id) { return false }
            if let snoozedUntil = budget.snoozedCandidateIDs[candidate.id], snoozedUntil > now {
                return false
            }
            return true
        }

        let sessionLocal = eligible
            .filter { !$0.kind.countsTowardDailyCap }
            .sorted { lhs, rhs in
                if lhs.kind.priority != rhs.kind.priority {
                    return lhs.kind.priority < rhs.kind.priority
                }
                return lhs.fireDate < rhs.fireDate
            }

        let proactiveEligible = eligible
            .filter(\.kind.countsTowardDailyCap)
            .sorted { lhs, rhs in
                if lhs.kind.priority != rhs.kind.priority {
                    return lhs.kind.priority < rhs.kind.priority
                }
                return lhs.fireDate < rhs.fireDate
            }

        let transitionCandidates = proactiveEligible.filter { $0.kind == .transitionShield }
        let otherProactive = proactiveEligible.filter { $0.kind != .transitionShield }

        let remainingSlots = max(0, NotificationPolicy.maxProactivePerDay - budget.deliveredCount)
        let selectedOther = Array(otherProactive.prefix(remainingSlots))
        let droppedProactiveCount = max(0, otherProactive.count - selectedOther.count)

        return SelectionResult(
            selected: selectedOther + transitionCandidates + sessionLocal,
            droppedProactiveCount: droppedProactiveCount
        )
    }
}
