import Foundation

/// Re-ranks proactive actions based on the user's primary ADHD focus challenge.
public enum ADHDProactiveRouting {
    private static let boostWeight = 2
    private static let suppressWeight = -3

    public static func rank(_ actions: [ProactiveAction], challenge: ADHDFocusChallenge = ADHDFocusChallenge.load()) -> [ProactiveAction] {
        actions
            .sorted { score($0, challenge: challenge) > score($1, challenge: challenge) }
    }

    public static func score(_ action: ProactiveAction, challenge: ADHDFocusChallenge) -> Int {
        var value = severityRank(action.severity)
        value += affinityBoost(action.kind, challenge: challenge)
        value += ProactiveFeedbackStore.boost(for: action.kind)
        if let expiresAt = action.expiresAt, expiresAt < Date().addingTimeInterval(5 * 60) {
            value += 1
        }
        return value
    }

    public static func rankFiltered(_ actions: [ProactiveAction], challenge: ADHDFocusChallenge = ADHDFocusChallenge.load(), now: Date = Date()) -> [ProactiveAction] {
        let visible = actions.filter { !ProactiveDismissStore.isSuppressed($0, now: now) }
            .filter { !ProactiveFeedbackStore.shouldSuppress(kind: $0.kind) }
        return rank(visible, challenge: challenge)
    }

    private static func severityRank(_ severity: ProactiveAction.Severity) -> Int {
        switch severity {
        case .high: return 30
        case .medium: return 20
        case .low: return 10
        }
    }

    private static func affinityBoost(_ kind: ProactiveAction.Kind, challenge: ADHDFocusChallenge) -> Int {
        switch challenge {
        case .timeBlindness:
            return weight(kind, boost: [.transitionShield, .waitingMode, .calendarChange, .pastDueStillToday], suppress: [.postCompletionMomentum, .morningPlanReview])
        case .taskInitiation:
            return weight(kind, boost: [.initiationBridge, .waitingMode, .captureResurrection], suppress: [.overloadedAfternoon, .middayCheckpoint])
        case .hyperfocus:
            return weight(kind, boost: [.hyperfocusBreak, .transitionShield, .noBreaksInLongBlock, .medicationNotScheduled], suppress: [.postCompletionMomentum])
        case .overwhelm:
            return weight(kind, boost: [.overwhelmCircuitBreaker, .overloadedAfternoon, .preSleepCrunch, .endOfDayClose], suppress: [.morningPlanReview, .postCompletionMomentum])
        case .workingMemory:
            return weight(kind, boost: [.captureResurrection, .medicationNotScheduled, .relationshipDrift], suppress: [.tooManyContextSwitches])
        case .emotionalRegulation:
            return weight(kind, boost: [.patternCoach, .endOfDayClose], suppress: [.middayCheckpoint, .pastDueStillToday])
        }
    }

    private static func weight(
        _ kind: ProactiveAction.Kind,
        boost: [ProactiveAction.Kind],
        suppress: [ProactiveAction.Kind]
    ) -> Int {
        if boost.contains(kind) { return boostWeight }
        if suppress.contains(kind) { return suppressWeight }
        return 0
    }
}
