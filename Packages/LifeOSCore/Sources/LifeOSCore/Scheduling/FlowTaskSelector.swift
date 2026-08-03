import Foundation

/// Selects a baseline hero task before constraint rules refine the outcome.
public enum FlowTaskSelector {

    /// Picks the best default hero from active pending tasks.
    public static func selectBaselineHero(from context: FlowSchedulingContext) -> LifeTask? {
        let tasks = context.heroEligibleTasks()
        guard !tasks.isEmpty else { return nil }

        let energy = EnergyLevel.from(score: context.energyScore)

        let sorted = tasks.sorted { lhs, rhs in
            let lhsScore = score(task: lhs, energy: energy, context: context)
            let rhsScore = score(task: rhs, energy: energy, context: context)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.title < rhs.title
        }

        return sorted.first
    }

    /// Shortest active task suitable for a time-constrained window.
    public static func selectShortestSuitableTask(
        from context: FlowSchedulingContext,
        maxMinutes: Int
    ) -> LifeTask? {
        context.heroEligibleTasks()
            .filter { effectiveMinutes(for: $0) <= maxMinutes }
            .sorted { lhs, rhs in
                let l = effectiveMinutes(for: lhs)
                let r = effectiveMinutes(for: rhs)
                if l != r { return l < r }
                return lhs.title < rhs.title
            }
            .first
    }

    /// Highest-priority task that exceeds the current energy budget.
    public static func selectHighEnergyTask(from context: FlowSchedulingContext) -> LifeTask? {
        let energy = EnergyLevel.from(score: context.energyScore)
        return context.heroEligibleTasks()
            .filter { !$0.isSuitableForEnergy(energy) }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
            .first
    }

    private static func score(task: LifeTask, energy: EnergyLevel, context: FlowSchedulingContext) -> Int {
        var value = 0
        if task.status == .inProgress { value += 100 }
        if task.status == .paused { value += 80 }
        value += task.priority.rawValue * 10
        if task.isSuitableForEnergy(energy) { value += 20 }
        if task.isOverdue { value += 15 }
        if task.isFixedTimeEvent && task.isActiveFixedTimeWindow(at: context.input.currentTime, calendar: context.calendar) {
            value += 200
        }
        if context.input.activeFlowSession?.taskID == task.id { value += 120 }

        let profile = task.resolvedSemanticProfile
        value += TaskSemanticScheduler.schedulingScoreAdjustment(
            profile: profile,
            context: context.semanticSchedulerContext
        )

        let required = TaskSemanticScheduler.effectiveEnergyLevel(profile: profile)
        if energy >= required { value += 10 } else { value -= 25 }

        return value
    }

    public static func effectiveMinutes(for task: LifeTask) -> Int {
        let remaining = task.remainingMinutes
        return remaining > 0 ? remaining : task.estimatedMinutes
    }
}

private extension EnergyLevel {
    static func from(score: Double) -> EnergyLevel {
        let clamped = min(max(score, 0), 1)
        if clamped <= 0.15 { return .recovery }
        if clamped <= 0.35 { return .low }
        if clamped <= 0.55 { return .moderate }
        if clamped <= 0.75 { return .high }
        return .peak
    }
}
