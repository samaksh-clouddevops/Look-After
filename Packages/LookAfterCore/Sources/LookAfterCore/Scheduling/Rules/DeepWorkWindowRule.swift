import Foundation

/// Promotes deep-work sessions when calendar gap and energy align.
public struct DeepWorkWindowRule: FlowSchedulingRuleProtocol {
    public let minGapMinutes: Int
    public let minEnergyScore: Double

    public let identifier = "DeepWorkWindowRule"

    public init(minGapMinutes: Int = 90, minEnergyScore: Double = 0.66) {
        self.minGapMinutes = minGapMinutes
        self.minEnergyScore = minEnergyScore
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        guard context.freeBlockMinutes >= minGapMinutes else { return }
        guard context.energyScore >= minEnergyScore else { return }
        guard state.actionType != .continue else { return }

        let deepCandidates = context.activeTasks
            .filter { task in
                let profile = task.resolvedSemanticProfile
                return TaskSemanticScheduler.isDeepWorkCandidate(profile: profile)
                    || task.difficulty == .hard
                    || task.estimatedMinutes >= 45
            }
            .filter { task in
                TaskSemanticScheduler.schedulability(
                    profile: task.resolvedSemanticProfile,
                    context: context.semanticSchedulerContext
                ).isAllowed
            }
            .sorted { lhs, rhs in
                let lDelay = lhs.resolvedSemanticProfile.consequenceOfDelay.severity
                let rDelay = rhs.resolvedSemanticProfile.consequenceOfDelay.severity
                if lDelay != rDelay { return lDelay > rDelay }
                return lhs.priority.rawValue > rhs.priority.rawValue
            }

        if let deepTask = deepCandidates.first {
            state.heroTask = deepTask
            state.actionType = .startDeep
            state.suggestedDurationMinutes = min(
                max(deepTask.estimatedMinutes, 45),
                context.freeBlockMinutes
            )
            state.reasoningLines.append("Deep-work window available (\(context.freeBlockMinutes) min free).")
            state.appliedRuleIDs.append(identifier)
        }
    }
}
