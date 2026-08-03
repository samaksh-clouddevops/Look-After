import Foundation

/// Adjusts action type and reschedules high-energy tasks when energy or HRV is low.
public struct LowEnergyRule: FlowSchedulingRuleProtocol {
    public let energyThreshold: Double
    public let hrvDeltaThreshold: Double

    public let identifier = "LowEnergyRule"

    public init(energyThreshold: Double = 0.35, hrvDeltaThreshold: Double = -0.15) {
        self.energyThreshold = energyThreshold
        self.hrvDeltaThreshold = hrvDeltaThreshold
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        let lowEnergy = context.energyScore <= energyThreshold
        let lowHRV = context.environment.hrvDelta <= hrvDeltaThreshold
        guard lowEnergy || lowHRV else { return }

        if state.actionType != .continue {
            state.actionType = .startSmall
        }

        state.suggestedDurationMinutes = min(state.suggestedDurationMinutes, 15)

        if state.heroTask?.isFixedTimeEvent == true { return }

        if let demanding = FlowTaskSelector.selectHighEnergyTask(from: context),
           !demanding.isFixedTimeEvent,
           state.heroTask?.id == demanding.id,
           state.heroTask?.isFixedTimeEvent != true,
           let alternative = context.activeTasks
            .filter({ candidate in
                guard candidate.id != demanding.id, !candidate.isFixedTimeEvent else { return false }
                return TaskSemanticScheduler.schedulability(
                    profile: candidate.resolvedSemanticProfile,
                    context: context.semanticSchedulerContext
                ).isAllowed
            })
            .sorted(by: { lhs, rhs in
                let lEnergy = TaskSemanticScheduler.effectiveEnergyLevel(profile: lhs.resolvedSemanticProfile)
                let rEnergy = TaskSemanticScheduler.effectiveEnergyLevel(profile: rhs.resolvedSemanticProfile)
                if lEnergy != rEnergy { return lEnergy.rawValue < rEnergy.rawValue }
                return FlowTaskSelector.effectiveMinutes(for: lhs) < FlowTaskSelector.effectiveMinutes(for: rhs)
            })
            .first {
            state.rescheduledTasks.append(
                RescheduleNotice(
                    taskID: demanding.id,
                    taskTitle: demanding.title,
                    explanation: "Moved to a later recovery window — it needs more energy."
                )
            )
            state.heroTask = alternative
            state.reasoningLines.append("Low energy — lighter task selected.")
        } else {
            state.reasoningLines.append("Low energy — shorter session recommended.")
        }

        state.appliedRuleIDs.append(identifier)
    }
}
