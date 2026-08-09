import Foundation

// MARK: - Weekly Review Aggregator

/// Pure functional engine: cascade history + life snapshot → `WeeklyReviewSummary`.
/// No I/O, no shared mutable state — safe to call from any context.
public enum WeeklyReviewAggregator {

    /// Minimum shift duration (minutes) counted as a flexible shift execution.
    public static let significantShiftMinutes = 30

    public static let equilibriumBase = 0.85
    public static let highLoadPenaltyPerDay = 0.05
    public static let sabotageBonusPerAuction = 0.08
    public static let equilibriumFloor = 0.2
    public static let equilibriumCeiling = 1.0

    /// Aggregate one week ending at `weekEnding` (inclusive end-of-day bound).
    ///
    /// - Parameters:
    ///   - logs: Structured cascade action records (any span; filtered to the week window).
    ///   - lifeState: Snapshot whose `activeTasks` supply completed focus hours + streak.
    ///   - weekEnding: Exclusive upper bound — window is the 7 days *prior* to this instant's end-of-day.
    ///   - calendar: Calendar used for day math.
    public static func aggregate(
        logs: [CascadeActionRecord],
        lifeState: LifeState,
        weekEnding: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyReviewSummary {
        let bounds = weekBounds(ending: weekEnding, calendar: calendar)
        let weekLogs = CascadeHistoryDedup.compact(
            logs.filter { $0.timestamp >= bounds.start && $0.timestamp < bounds.endExclusive },
            calendar: calendar
        )

        let sabotageLogs = weekLogs.filter { $0.kind == .sabotageAuction }
        let sabotageCount = sabotageLogs.count
        let timeReclaimedHours = sabotageLogs.reduce(0.0) { $0 + Double($1.durationMinutes) } / 60.0

        let flexibleShifts = weekLogs.filter {
            $0.kind == .shiftedLater && $0.durationMinutes >= significantShiftMinutes
        }.count

        let superseded = weekLogs.filter { $0.kind == .superseded }.count
        let expired = weekLogs.filter { $0.kind == .expired }.count

        // Focus hours: completed tasks whose completion falls inside the week window.
        let completedInWindow = lifeState.activeTasks.filter { task in
            guard task.status == .completed, let completedAt = task.completedAt else { return false }
            return completedAt >= bounds.start && completedAt < bounds.endExclusive
        }
        let focusMinutes = completedInWindow.reduce(0) { partial, task in
            partial + (task.actualMinutes ?? task.estimatedMinutes)
        }
        let focusHours = Double(focusMinutes) / 60.0

        let highLoad = max(0, lifeState.consecutiveHighLoadDays)
        let equilibrium = computeEquilibrium(
            highLoadStreakDays: highLoad,
            sabotageAuctionsTriggered: sabotageCount
        )

        return WeeklyReviewSummary(
            id: "week-\(TelemetryLogRotation.dayKey(for: bounds.start, calendar: calendar))",
            weekStartDate: bounds.start,
            weekEndDate: bounds.endInclusive,
            totalFocusHoursCompleted: focusHours,
            timeReclaimedHours: timeReclaimedHours,
            highLoadStreakDays: highLoad,
            sabotageAuctionsTriggered: sabotageCount,
            tasksSupersededCount: superseded,
            tasksExpiredCount: expired,
            flexibleShiftsExecuted: flexibleShifts,
            equilibriumScore: equilibrium
        )
    }

    /// Convenience: build records from a single `ConflictCascadeResult`, then aggregate.
    public static func aggregate(
        decisions: [ConflictCascadeDecision],
        triggeredRecoveryLock: Bool,
        recoveryDurationMinutes: Int = 0,
        lifeState: LifeState,
        weekEnding: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyReviewSummary {
        let records = CascadeActionRecordBuilder.records(
            from: decisions,
            triggeredRecoveryLock: triggeredRecoveryLock,
            recoveryDurationMinutes: recoveryDurationMinutes,
            now: now
        )
        return aggregate(logs: records, lifeState: lifeState, weekEnding: weekEnding, calendar: calendar)
    }

    // MARK: - Equilibrium

    public static func computeEquilibrium(
        highLoadStreakDays: Int,
        sabotageAuctionsTriggered: Int
    ) -> Double {
        var score = equilibriumBase
        score -= Double(max(0, highLoadStreakDays)) * highLoadPenaltyPerDay
        score += Double(max(0, sabotageAuctionsTriggered)) * sabotageBonusPerAuction
        return min(equilibriumCeiling, max(equilibriumFloor, score))
    }

    // MARK: - Week window

    /// Seven-day window ending at end-of-day of `weekEnding`.
    public static func weekBounds(
        ending weekEnding: Date,
        calendar: Calendar = .current
    ) -> (start: Date, endInclusive: Date, endExclusive: Date) {
        let endDay = calendar.startOfDay(for: weekEnding)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay),
              let start = calendar.date(byAdding: .day, value: -6, to: endDay) else {
            return (endDay, endDay, endDay)
        }
        // Inclusive calendar end = start of end day (display); exclusive bound for filtering.
        return (start, endDay, endExclusive)
    }
}

// MARK: - Record builder

/// Maps cascade decisions → structured `CascadeActionRecord`s (pure).
public enum CascadeActionRecordBuilder {

    public static func records(
        from decisions: [ConflictCascadeDecision],
        triggeredRecoveryLock: Bool = false,
        recoveryDurationMinutes: Int = 0,
        now: Date = Date()
    ) -> [CascadeActionRecord] {
        var out: [CascadeActionRecord] = []

        if triggeredRecoveryLock
            || decisions.contains(where: {
                $0.reason.contains("sabotage") && !$0.reason.contains("override")
                    || $0.reason.contains("recovery") && !$0.reason.contains("override")
            }) {
            out.append(
                CascadeActionRecord(
                    kind: .sabotageAuction,
                    timestamp: now,
                    durationMinutes: max(0, recoveryDurationMinutes),
                    reason: "sabotage_auction"
                )
            )
        }

        for d in decisions {
            guard let kind = mapKind(d.action) else { continue }
            let minutes: Int
            switch d.action {
            case .shiftLater:
                minutes = d.shiftMinutes ?? 0
            case .compress:
                minutes = d.compressDeltaMinutes ?? 0
            default:
                minutes = 0
            }
            out.append(
                CascadeActionRecord(
                    kind: kind,
                    timestamp: now,
                    durationMinutes: minutes,
                    taskID: d.taskID,
                    reason: d.reason
                )
            )
        }
        return out
    }

    private static func mapKind(_ action: ConflictCascadeAction) -> CascadeActionKind? {
        switch action {
        case .keep: return nil
        case .shiftLater: return .shiftedLater
        case .compress: return .compressed
        case .deferNextGap: return .deferred
        case .park: return .parked
        case .expired: return .expired
        case .superseded: return .superseded
        }
    }
}
