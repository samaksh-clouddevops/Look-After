import Foundation

/// Pure, deterministic scheduling engine composing independently testable rules.
public struct FlowSchedulingEngine: FlowSchedulingEngineProtocol {

    public let rules: [AnyFlowSchedulingRule]
    public let calendar: Calendar

    public init(
        rules: [AnyFlowSchedulingRule] = FlowSchedulingEngine.defaultRules,
        calendar: Calendar = .current
    ) {
        self.rules = rules
        self.calendar = calendar
    }

    /// Default rule pipeline ordered by evaluation priority.
    public static let defaultRules: [AnyFlowSchedulingRule] = [
        AnyFlowSchedulingRule(ContinueTaskRule()),
        AnyFlowSchedulingRule(FixedTimeEventRule()),
        AnyFlowSchedulingRule(MeetingSoonRule()),
        AnyFlowSchedulingRule(LowEnergyRule()),
        AnyFlowSchedulingRule(DeepWorkWindowRule()),
        AnyFlowSchedulingRule(DeferralRule()),
        AnyFlowSchedulingRule(BatteryRule()),
        AnyFlowSchedulingRule(CalendarGapRule())
    ]

    public func schedule(from input: FlowDirectorInput) -> FlowSchedulingResult {
        let context = FlowSchedulingContext(input: input, calendar: calendar)

        var state = MutableSchedulingState()
        if state.heroTask == nil {
            state.heroTask = FlowTaskSelector.selectBaselineHero(from: context)
            if let hero = state.heroTask {
                state.suggestedDurationMinutes = FlowTaskSelector.effectiveMinutes(for: hero)
            }
        }

        for rule in rules {
            rule.apply(to: &state, context: context)
        }

        state.clampDuration()

        let personality = FlowPersonality.from(energyScore: context.energyScore)
        let prediction = makePrediction(from: state, context: context)

        return FlowSchedulingResult(
            heroTask: state.heroTask,
            prediction: prediction,
            flowPersonality: personality,
            rescheduledTasks: state.rescheduledTasks,
            coachMoment: state.coachMoment,
            flowWindow: state.flowWindow,
            nextCalendarEvent: state.nextCalendarEvent,
            energyScore: context.energyScore,
            focusReadiness: context.focusReadiness,
            confidence: 0
        )
    }

    private func makePrediction(
        from state: MutableSchedulingState,
        context: FlowSchedulingContext
    ) -> FlowPrediction? {
        guard let hero = state.heroTask else { return nil }

        let duration = state.suggestedDurationMinutes
        let label = UserFacingCopy.actionButtonLabel(for: state.actionType, task: hero)
        let subtitle = UserFacingCopy.actionDurationSubtitle(minutes: duration)
        let reasoning = state.reasoningLines.isEmpty
            ? "Selected based on current context."
            : state.reasoningLines.joined(separator: " ")

        return FlowPrediction(
            id: "prediction-\(hero.id)",
            taskID: hero.id,
            suggestedDurationMinutes: duration,
            buttonLabel: label,
            buttonSubtitle: subtitle,
            confidence: 0,
            reasoning: reasoning,
            actionType: state.actionType
        )
    }

}
