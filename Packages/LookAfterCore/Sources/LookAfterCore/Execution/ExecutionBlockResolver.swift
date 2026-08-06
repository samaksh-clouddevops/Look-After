import Foundation

/// Pure domain resolver — wall-clock → active execution block.
/// All Execution Layer state transitions originate here (UDF).
public enum ExecutionBlockResolver {

    /// Minimum confidence for a `.flexible` block to own the environment.
    public static let highFlexibleConfidenceThreshold: Double = 0.72

    public struct Candidate: Sendable, Equatable {
        public var task: LifeTask
        public var interval: TaskScheduleInterval
        public var confidence: Double

        public init(task: LifeTask, interval: TaskScheduleInterval, confidence: Double = 1.0) {
            self.task = task
            self.interval = interval
            self.confidence = min(1, max(0, confidence))
        }
    }

    // MARK: - Public API

    /// Resolves the active execution snapshot for `now`.
    public static func resolve(
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current,
        confidenceForTask: ((LifeTask, Date) -> Double)? = nil
    ) -> ExecutionBlockSnapshot {
        let day = calendar.startOfDay(for: now)
        let dayTasks = TaskScheduleQuery.tasksForDay(
            from: tasks,
            allTasks: tasks,
            day: day,
            calendar: calendar
        ).filter { $0.status.isActive }

        let candidates = dayTasks.compactMap { task -> Candidate? in
            guard let interval = TaskScheduleInterval.window(for: task, on: day, calendar: calendar) else {
                return nil
            }
            let confidence = confidenceForTask?(task, now) ?? defaultConfidence(for: task, at: now, calendar: calendar)
            return Candidate(task: task, interval: interval, confidence: confidence)
        }
        .sorted { $0.interval.start < $1.interval.start }

        if let active = bestActiveCandidate(from: candidates, now: now) {
            return snapshot(for: active, candidates: candidates, now: now, calendar: calendar)
        }

        return fluidGapSnapshot(candidates: candidates, now: now, calendar: calendar)
    }

    /// When multiple tasks overlap `now`, prefer anchored deep-work over life commitments.
    public static func bestActiveCandidate(from candidates: [Candidate], now: Date) -> Candidate? {
        candidates
            .filter { $0.interval.start <= now && now < $0.interval.end }
            .max(by: { candidatePriority($0) < candidatePriority($1) })
    }

    public static func candidatePriority(_ candidate: Candidate) -> Int {
        var score = 0
        let task = candidate.task
        switch task.timeConstraintValue {
        case .anchored: score += 10_000
        case .flexible: score += 5_000
        case .fluid: score += 1_000
        }
        switch FocusTaskCategory.resolve(for: task) {
        case .deepWork: score += 2_000
        case .creative: score += 1_500
        case .admin, .health: score += 500
        case .recovery, .social, .fluidGap: score += 100
        }
        if task.isLifeCommitmentTask { score -= 3_000 }
        score += min(999, Int(candidate.interval.end.timeIntervalSince(candidate.interval.start) / 60))
        return score
    }

    /// Legacy single-match path — kept for tests.
    static func firstActiveCandidate(from candidates: [Candidate], now: Date) -> Candidate? {
        candidates.first(where: { $0.interval.start <= now && now < $0.interval.end })
    }

    /// Whether `task` is scheduled in an active window at `now`.
    public static func isInActiveWindow(
        _ task: LifeTask,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: now)
        guard let interval = TaskScheduleInterval.window(for: task, on: day, calendar: calendar) else {
            return false
        }
        return interval.start <= now && now < interval.end
    }

    /// Whether the snapshot should own Focus Filter + Live Activity projection.
    public static func shouldProjectEnvironment(for snapshot: ExecutionBlockSnapshot) -> Bool {
        switch snapshot.surfaceMode {
        case .anchored:
            return true
        case .flexible:
            return snapshot.confidence >= highFlexibleConfidenceThreshold
        case .recovery:
            return true
        case .fluidGap:
            // Minimal island only when gap is meaningful (≥ 5 minutes remaining).
            return snapshot.remainingSeconds >= 5 * 60
        case .idle:
            return false
        }
    }

    // MARK: - Snapshot builders

    private static func snapshot(
        for candidate: Candidate,
        candidates: [Candidate],
        now: Date,
        calendar: Calendar
    ) -> ExecutionBlockSnapshot {
        let task = candidate.task
        let category = FocusTaskCategory.resolve(for: task)
        let constraint = task.timeConstraintValue
        let mode = surfaceMode(category: category, constraint: constraint, confidence: candidate.confidence)
        let progress = progressFraction(
            start: candidate.interval.start,
            end: candidate.interval.end,
            now: now
        )
        let nextUp = nextUpSummary(after: candidate, candidates: candidates, now: now, calendar: calendar)

        return ExecutionBlockSnapshot(
            id: "block-\(task.id)",
            taskID: task.id,
            taskTitle: task.title,
            category: category,
            surfaceMode: mode,
            constraintType: constraint,
            windowStart: candidate.interval.start,
            windowEnd: candidate.interval.end,
            progressFraction: progress,
            nextUpSummary: nextUp,
            confidence: candidate.confidence,
            generatedAt: now
        )
    }

    private static func fluidGapSnapshot(
        candidates: [Candidate],
        now: Date,
        calendar: Calendar
    ) -> ExecutionBlockSnapshot {
        guard let next = candidates.first(where: { $0.interval.start > now }) else {
            return .idle
        }

        let minutes = max(1, Int(next.interval.start.timeIntervalSince(now) / 60))
        let nextLabel = "\(minutes)m until \(next.task.title)"
        let dayEnd = DayBoundaryPlanner.actionableDayEnd(on: now, calendar: calendar)
        let gapEnd = min(next.interval.start, dayEnd)

        return ExecutionBlockSnapshot(
            id: "gap-\(Int(now.timeIntervalSince1970))",
            taskID: nil,
            taskTitle: "Fluid Gap",
            category: .fluidGap,
            surfaceMode: .fluidGap,
            constraintType: .fluid,
            windowStart: now,
            windowEnd: gapEnd,
            progressFraction: 0,
            nextUpSummary: nextLabel,
            confidence: 1,
            generatedAt: now
        )
    }

    // MARK: - Helpers

    private static func surfaceMode(
        category: FocusTaskCategory,
        constraint: TimeConstraint,
        confidence: Double
    ) -> ExecutionSurfaceMode {
        // Recovery always projects a soft ambient surface (no countdown pressure).
        if category == .recovery {
            return .recovery
        }
        switch constraint {
        case .anchored:
            return .anchored
        case .flexible:
            // High-confidence flexible owns the environment; low confidence waits.
            return confidence >= highFlexibleConfidenceThreshold ? .flexible : .idle
        case .fluid:
            return .fluidGap
        }
    }

    private static func progressFraction(start: Date, end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    private static func nextUpSummary(
        after active: Candidate,
        candidates: [Candidate],
        now: Date,
        calendar: Calendar
    ) -> String {
        if let next = candidates.first(where: { $0.interval.start >= active.interval.end }) {
            let minutes = max(1, Int(next.interval.start.timeIntervalSince(active.interval.end) / 60))
            if minutes <= 1 {
                return "Next Up: \(next.task.title)"
            }
            let gapMinutes = max(0, Int(next.interval.start.timeIntervalSince(active.interval.end) / 60))
            if gapMinutes >= 5 {
                return "Next Up: \(gapMinutes)m Fluid Gap · then \(next.task.title)"
            }
            return "Next Up: \(next.task.title)"
        }

        let endLabel = ScheduleTimeFormatting.timeLabel(active.interval.end, calendar: calendar)
        return "Ends at \(endLabel)"
    }

    private static func defaultConfidence(
        for task: LifeTask,
        at now: Date,
        calendar: Calendar
    ) -> Double {
        switch task.timeConstraintValue {
        case .anchored:
            return 1.0
        case .flexible:
            // Fixed-mode legacy tasks count as high confidence flexible when scheduled.
            if task.schedulingModeValue == .fixedTime { return 0.9 }
            if task.isFixedTimeEvent { return 0.95 }
            // Deep work / important work defaults higher so execution layer engages.
            let category = FocusTaskCategory.resolve(for: task)
            switch category {
            case .deepWork, .creative, .health:
                return 0.8
            case .admin:
                return 0.75
            case .recovery, .social, .fluidGap:
                return 0.7
            }
        case .fluid:
            return 0.5
        }
    }
}
