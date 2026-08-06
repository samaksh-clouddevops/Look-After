import Foundation

// MARK: - What-If Simulation Engine (Life schedule)

/// Pure functional what-if planner.
/// Deep-copies `LifeState`, injects hypothetical tasks, dry-runs cascade reconcile,
/// and diffs baseline vs simulated outcomes — never mutates persistent stores.
public enum SimulationEngine {

    /// Run a what-if against a baseline life state.
    /// - Parameters:
    ///   - baselineState: Live snapshot (copied; never mutated).
    ///   - hypotheticalTasks: Tasks to inject for the dry-run.
    ///   - day: Calendar day to reconcile.
    public static func simulate(
        baselineState: LifeState,
        hypotheticalTasks: [LifeTask],
        day: Date = Date(),
        model: LifeModel? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = 5
    ) -> SimulationResult {
        let dayStart = calendar.startOfDay(for: day)
        // Value copy of baseline — structs already use value semantics.
        let baselineCopy = LifeState(
            activeTasks: baselineState.activeTasks,
            consecutiveHighLoadDays: baselineState.consecutiveHighLoadDays
        )

        var injected = hypotheticalTasks.map { task -> LifeTask in
            var copy = task
            if copy.scheduledDate == nil {
                copy.scheduledDate = dayStart
            }
            // Untimed drafts get a default mid-morning window so cascade can evaluate them.
            if copy.scheduledTime == nil {
                let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: dayStart) ?? dayStart
                copy.scheduledTime = start
                copy.scheduledEndTime = start.addingTimeInterval(
                    TimeInterval(max(copy.estimatedMinutes, 15) * 60)
                )
            }
            if copy.timeConstraint == nil {
                copy.timeConstraint = copy.schedulingMode == .fixedTime ? .anchored : .fluid
            }
            if copy.status != .pending && !copy.status.isActive {
                copy.status = .pending
            }
            return copy
        }

        var simulatedState = baselineCopy
        simulatedState.activeTasks.append(contentsOf: injected)

        let baselineReconciled = DayScheduleReconciler.reconcile(
            state: baselineCopy,
            on: dayStart,
            model: model,
            now: now,
            calendar: calendar,
            bufferMinutes: bufferMinutes,
            options: .dryRun
        )

        let simulatedReconciled = DayScheduleReconciler.reconcile(
            state: simulatedState,
            on: dayStart,
            model: model,
            now: now,
            calendar: calendar,
            bufferMinutes: bufferMinutes,
            options: .dryRun
        )

        let streak = HighLoadDayEvaluator.consecutiveHighLoadDays(
            tasks: simulatedReconciled.tasks,
            now: now,
            calendar: calendar
        )
        // Include today when today's load is already high after injection.
        let todayHigh = HighLoadDayEvaluator.isHighLoadDay(
            tasks: simulatedReconciled.tasks,
            on: dayStart,
            calendar: calendar
        )
        let simulatedStreak = streak + (todayHigh ? 1 : 0)
        let baselineTodayHigh = HighLoadDayEvaluator.isHighLoadDay(
            tasks: baselineReconciled.tasks,
            on: dayStart,
            calendar: calendar
        )
        let baselineStreak = baselineCopy.consecutiveHighLoadDays + (baselineTodayHigh ? 1 : 0)

        let finalState = LifeState(
            activeTasks: simulatedReconciled.tasks,
            consecutiveHighLoadDays: simulatedStreak
        )

        let impact = buildImpact(
            baselineCascade: baselineReconciled.cascade,
            simulatedCascade: simulatedReconciled.cascade,
            baselineStreak: baselineStreak,
            simulatedStreak: simulatedStreak,
            hypotheticalIDs: injected.map(\.id),
            now: now,
            calendar: calendar
        )

        return SimulationResult(
            simulatedState: finalState,
            impact: impact,
            baselineState: baselineCopy,
            day: dayStart,
            hypotheticalTasks: injected
        )
    }

    /// Convenience overload for a single hypothetical task.
    public static func simulate(
        baselineState: LifeState,
        hypotheticalTask: LifeTask,
        day: Date = Date(),
        model: LifeModel? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = 5
    ) -> SimulationResult {
        simulate(
            baselineState: baselineState,
            hypotheticalTasks: [hypotheticalTask],
            day: day,
            model: model,
            now: now,
            calendar: calendar,
            bufferMinutes: bufferMinutes
        )
    }

    // MARK: - Diff

    private static func buildImpact(
        baselineCascade: ConflictCascadeResult,
        simulatedCascade: ConflictCascadeResult,
        baselineStreak: Int,
        simulatedStreak: Int,
        hypotheticalIDs: [String],
        now: Date,
        calendar: Calendar
    ) -> SimulationImpactReport {
        let baseParked = Set(baselineCascade.parkedTaskIDs)
        let simParked = Set(simulatedCascade.parkedTaskIDs)
        let parkedDelta = simParked.subtracting(baseParked).count

        let baseSuperseded = baselineCascade.decisions.filter { $0.action == .superseded }.count
        let simSuperseded = simulatedCascade.decisions.filter { $0.action == .superseded }.count
        let supersededDelta = max(0, simSuperseded - baseSuperseded)

        let highLoadDelta = simulatedStreak - baselineStreak

        // Project sabotage auctions from simulated streak (same thresholds as GapAuction).
        var sabotageCount = 0
        if simulatedCascade.triggeredRecoveryLock {
            sabotageCount += 1
        }
        let auctionContext = GapAuctionContext(
            consecutiveHighLoadDays: max(0, simulatedStreak),
            gapMinutes: 60,
            now: now,
            sabotageCooldownActive: false,
            calendar: calendar
        )
        if auctionContext.shouldForceRecoveryBlock {
            sabotageCount = max(sabotageCount, 1)
        }
        // Baseline may already hold a recovery lock — only count net-new triggers.
        if baselineCascade.triggeredRecoveryLock && sabotageCount > 0 {
            sabotageCount = max(0, sabotageCount - 1)
        }

        let (message, severity) = summarize(
            parkedDelta: parkedDelta,
            supersededDelta: supersededDelta,
            highLoadDelta: highLoadDelta,
            sabotageCount: sabotageCount
        )

        return SimulationImpactReport(
            parkedTaskDelta: parkedDelta,
            sabotageAuctionsTriggered: sabotageCount,
            supersededTasksDelta: supersededDelta,
            highLoadStreakDelta: highLoadDelta,
            simulatedParkedCount: simParked.count,
            simulatedSupersededCount: simSuperseded,
            hypotheticalTaskIDs: hypotheticalIDs,
            summaryMessage: message,
            severity: severity
        )
    }

    private static func summarize(
        parkedDelta: Int,
        supersededDelta: Int,
        highLoadDelta: Int,
        sabotageCount: Int
    ) -> (String, SimulationImpactReport.Severity) {
        if parkedDelta <= 0 && supersededDelta <= 0 && highLoadDelta <= 0 && sabotageCount == 0 {
            return ("Schedule absorbs this smoothly", .success)
        }
        if parkedDelta >= 2 || highLoadDelta >= 2 || sabotageCount > 0 {
            var parts: [String] = []
            if parkedDelta > 0 {
                parts.append("+\(parkedDelta) parked")
            }
            if highLoadDelta > 0 {
                parts.append("high-load streak +\(highLoadDelta)")
            }
            if sabotageCount > 0 {
                parts.append("sabotage auction likely")
            }
            if supersededDelta > 0 {
                parts.append("+\(supersededDelta) superseded")
            }
            return (parts.joined(separator: " · "), .critical)
        }
        if parkedDelta > 0 || supersededDelta > 0 || highLoadDelta > 0 {
            var parts: [String] = []
            if parkedDelta > 0 { parts.append("+\(parkedDelta) task parked") }
            if supersededDelta > 0 { parts.append("+\(supersededDelta) superseded") }
            if highLoadDelta > 0 { parts.append("load streak +\(highLoadDelta)") }
            return (parts.joined(separator: " · "), .warning)
        }
        return ("Minor schedule reshuffle", .neutral)
    }
}
