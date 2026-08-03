import Foundation

/// Offers a micro-chunk coach moment when a task has been deferred repeatedly.
public struct DeferralRule: FlowSchedulingRuleProtocol {
    public let deferralThreshold: Int

    public let identifier = "DeferralRule"

    public init(deferralThreshold: Int = 3) {
        self.deferralThreshold = deferralThreshold
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        guard let hero = state.heroTask else { return }
        let count = context.deferralCount(for: hero.id)
        guard count >= deferralThreshold else { return }

        state.actionType = .tryMicro
        state.suggestedDurationMinutes = min(state.suggestedDurationMinutes, 5)
        state.coachMoment = CoachMoment(
            message: UserFacingCopy.microActionMessage(deferralCount: count),
            primaryAction: UserFacingCopy.microActionLabel(task: hero),
            secondaryAction: "Not now",
            momentType: .microChunkOffer
        )
        state.reasoningLines.append("Repeated deferrals detected — micro-chunk offered.")
        state.appliedRuleIDs.append(identifier)
    }
}
