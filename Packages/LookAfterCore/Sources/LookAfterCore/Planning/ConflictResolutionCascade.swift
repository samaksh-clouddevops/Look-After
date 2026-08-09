import Foundation

// MARK: - Cascade actions (deterministic, no user prompts)

/// Outcome applied to a single task during conflict auto-triage.
public enum ConflictCascadeAction: String, Sendable, Equatable {
    /// Left in place (winner / immovable).
    case keep
    /// Shifted later same day into an open slot.
    case shiftLater
    /// Shortened duration to fit a gap (never below minimum).
    case compress
    /// Deferred to the next open gap (not same-clock) as fluid.
    case deferNextGap
    /// Unscheduled + appended to parked recovery queue.
    case park
    /// Ephemeral window missed — contextual kill, never parked.
    case expired
    /// Semantic collision — duplicate already on destination day.
    case superseded
}

public struct ConflictCascadeDecision: Sendable, Equatable {
    public var taskID: String
    public var action: ConflictCascadeAction
    public var reason: String
    /// Minutes shifted later (Stage 1). Used by CascadeDistiller (>30m = macro).
    public var shiftMinutes: Int?
    /// True when compress stopped at the viable floor (material change).
    public var compressHitViableFloor: Bool?
    /// Minutes removed by compress.
    public var compressDeltaMinutes: Int?

    public init(
        taskID: String,
        action: ConflictCascadeAction,
        reason: String,
        shiftMinutes: Int? = nil,
        compressHitViableFloor: Bool? = nil,
        compressDeltaMinutes: Int? = nil
    ) {
        self.taskID = taskID
        self.action = action
        self.reason = reason
        self.shiftMinutes = shiftMinutes
        self.compressHitViableFloor = compressHitViableFloor
        self.compressDeltaMinutes = compressDeltaMinutes
    }
}

public struct ConflictCascadeResult: Sendable, Equatable {
    public var tasks: [LifeTask]
    public var decisions: [ConflictCascadeDecision]
    public var changedTaskIDs: Set<String>
    /// Always empty when cascade completes — day is auto-resolved.
    public var unresolvedTaskIDs: Set<String>
    /// Task IDs appended to the parked recovery queue this run.
    public var parkedTaskIDs: [String]
    /// True when a recovery/sabotage lock is present among results.
    public var triggeredRecoveryLock: Bool

    public init(
        tasks: [LifeTask],
        decisions: [ConflictCascadeDecision] = [],
        changedTaskIDs: Set<String> = [],
        unresolvedTaskIDs: Set<String> = [],
        parkedTaskIDs: [String] = [],
        triggeredRecoveryLock: Bool = false
    ) {
        self.tasks = tasks
        self.decisions = decisions
        self.changedTaskIDs = changedTaskIDs
        self.unresolvedTaskIDs = unresolvedTaskIDs
        self.parkedTaskIDs = parkedTaskIDs
        self.triggeredRecoveryLock = triggeredRecoveryLock
    }
}

// MARK: - Engine

/// Deterministic cascade for overlapping blocks.
/// Priority (high → low): anchored > flexible > fluid, then life commitments,
/// priority, earlier start. No manual resolution prompts — every clash is triaged.
public enum ConflictResolutionCascade {

    public static let defaultBufferMinutes = 5
    /// Extra buffer around newly deferred placements so we don't guarantee a second cascade.
    public static let placementBufferMinutes = 10
    public static let dayEndHour = 21
    /// Domino dampener: if a same-day shift would force more than this many
    /// subsequent pool tasks to move, skip Stage 1 and jump to defer/park.
    public static let maxDominoShifts = 2
    /// Search horizon for next-gap deferral (no hard 7-day park force).
    public static let deferralHorizonDays = 28

    public static func resolve(
        tasks: [LifeTask],
        on day: Date,
        model: LifeModel? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        bufferMinutes: Int = defaultBufferMinutes,
        parkedQueue: ParkedTaskQueueStore? = nil,
        remainingTasks: [LifeTask] = [],
        vaultFloorsByHash: [String: Int] = [:]
    ) -> ConflictCascadeResult {
        let dayStart = calendar.startOfDay(for: day)
        // Full world for tomorrow-gap search (includes off-day tasks).
        let universe = remainingTasks.isEmpty ? tasks : remainingTasks

        var pool = tasks.filter { isActiveOnDay($0, day: dayStart, calendar: calendar) }
        guard pool.count > 1 else {
            return ConflictCascadeResult(tasks: tasks)
        }

        pool.sort { lhs, rhs in
            let rl = rank(lhs), rr = rank(rhs)
            if rl != rr { return rl > rr }
            let ls = TaskScheduleInterval.window(for: lhs, on: dayStart, calendar: calendar)?.start ?? .distantFuture
            let rs = TaskScheduleInterval.window(for: rhs, on: dayStart, calendar: calendar)?.start ?? .distantFuture
            if ls != rs { return ls < rs }
            return lhs.id < rhs.id
        }

        var blocked: [TaskScheduleInterval] = []
        var decisions: [ConflictCascadeDecision] = []
        var changed: Set<String> = []
        var parkedIDs: [String] = []
        var byID = Dictionary.uniquingFirstValue(tasks.map { ($0.id, $0) })
        var shiftCount = 0 // domino dampener counter for this root resolution

        // Destination-day actives for collision (exclude self).
        let destinationActives = pool.filter { $0.status.isActive }

        for var task in pool {
            // Stage 0 — The Reaper: expire / supersede before any move.
            switch TaskReaper.verdict(for: task, now: now, destinationDayTasks: destinationActives, calendar: calendar) {
            case .expire:
                task.status = .expired
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                decisions.append(.init(taskID: task.id, action: .expired, reason: "reaper_expired"))
                changed.insert(task.id)
                byID[task.id] = task
                continue
            case .supersede:
                task.status = .superseded
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                decisions.append(.init(taskID: task.id, action: .superseded, reason: "semantic_collision"))
                changed.insert(task.id)
                byID[task.id] = task
                continue
            case .alive:
                break
            }

            guard var interval = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) else {
                continue
            }

            if !blocked.contains(where: { interval.overlaps($0) }) {
                blocked.append(interval)
                blocked.sort { $0.start < $1.start }
                decisions.append(.init(taskID: task.id, action: .keep, reason: "no_overlap"))
                byID[task.id] = task
                continue
            }

            // Mis-anchored meal routines must shift — not preserve overlap as anchored.
            if task.timeConstraintValue == .anchored,
               OnboardingTaskSeeder.isMealRoutineTitle(task.title) {
                task.applyTimeConstraint(.flexible)
            }

            let hash = BehavioralSemanticHash.make(for: task)
            let viableMin = task.minimumViableDurationValue(vaultFloorMinutes: vaultFloorsByHash[hash])
            let allowShift = canMove(task) && shiftCount < maxDominoShifts
            let policy = TaskEphemeralityDefaults.expiration(for: task)

            // Stage 1: shift later same day — capped by temporal bounding box.
            if allowShift,
               let open = findOpenStart(
                   durationMinutes: interval.durationMinutes,
                   blocked: blocked,
                   after: interval.start,
                   dayStart: dayStart,
                   bufferMinutes: bufferMinutes,
                   calendar: calendar
               ),
               TaskReaper.allowsStart(open, for: task, calendar: calendar) {
                let priorStart = interval.start
                applyStart(open, to: &task, on: dayStart, calendar: calendar)
                if let updated = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) {
                    interval = updated
                    blocked.append(interval)
                    blocked.sort { $0.start < $1.start }
                }
                let deltaMin = max(0, Int(open.timeIntervalSince(priorStart) / 60.0))
                decisions.append(.init(
                    taskID: task.id,
                    action: .shiftLater,
                    reason: "shifted_after_blocker",
                    shiftMinutes: deltaMin
                ))
                changed.insert(task.id)
                shiftCount += 1
                byID[task.id] = task
                continue
            }

            // Bounding box blocked all same-day shifts → ephemeral kill instead of night-slot park.
            if allowShift,
               TaskEphemeralityDefaults.boundingBox(for: task) != nil,
               policy == .endOfDay || {
                   if case .strictWindow = policy { return true }
                   return false
               }() {
                task.status = .expired
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                decisions.append(.init(taskID: task.id, action: .expired, reason: "reaper_outside_bounding_box"))
                changed.insert(task.id)
                byID[task.id] = task
                continue
            }

            // Stage 2: compress only down to minimumViableDuration (never useless stubs).
            if canCompress(task),
               let gap = findCompressibleGap(
                   preferredStart: interval.start,
                   minMinutes: viableMin,
                   preferredMinutes: interval.durationMinutes,
                   blocked: blocked,
                   dayStart: dayStart,
                   bufferMinutes: bufferMinutes,
                   calendar: calendar
               ),
               gap.minutes >= viableMin {
                let priorMinutes = interval.durationMinutes
                task.estimatedMinutes = gap.minutes
                applyStart(gap.start, to: &task, on: dayStart, calendar: calendar)
                if let updated = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) {
                    blocked.append(updated)
                    blocked.sort { $0.start < $1.start }
                }
                let hitFloor = gap.minutes <= viableMin + 1
                decisions.append(.init(
                    taskID: task.id,
                    action: .compress,
                    reason: "compressed_to_\(gap.minutes)m_floor_\(viableMin)",
                    compressHitViableFloor: hitFloor,
                    compressDeltaMinutes: max(0, priorMinutes - gap.minutes)
                ))
                changed.insert(task.id)
                byID[task.id] = task
                continue
            }

            // Ephemeral tasks never park or defer across days — reaper kill.
            if policy == .endOfDay || {
                if case .strictWindow = policy { return true }
                return false
            }() {
                task.status = .expired
                task.scheduledTime = nil
                task.scheduledEndTime = nil
                decisions.append(.init(taskID: task.id, action: .expired, reason: "reaper_no_valid_same_day_slot"))
                changed.insert(task.id)
                byID[task.id] = task
                continue
            }

            // Stage 3: defer to next *available optimal gap* — strip clock, become fluid.
            // Collision check on destination day before placing.
            if canDefer(task),
               let placement = findNextAvailableGap(
                   durationMinutes: max(task.estimatedMinutes, viableMin),
                   from: dayStart,
                   excludingTaskID: task.id,
                   universe: universe.map { byID[$0.id] ?? $0 },
                   horizonDays: deferralHorizonDays,
                   bufferMinutes: max(bufferMinutes, placementBufferMinutes),
                   calendar: calendar
               ) {
                let destTasks = universe.map { byID[$0.id] ?? $0 }.filter {
                    guard let d = $0.scheduledDate else { return false }
                    return calendar.isDate(d, inSameDayAs: placement.day) && $0.status.isActive
                }
                switch TaskReaper.verdict(for: task, now: now, destinationDayTasks: destTasks, calendar: calendar) {
                case .supersede:
                    task.status = .superseded
                    task.scheduledTime = nil
                    task.scheduledEndTime = nil
                    decisions.append(.init(taskID: task.id, action: .superseded, reason: "semantic_collision_on_defer"))
                    changed.insert(task.id)
                    byID[task.id] = task
                    continue
                case .expire:
                    task.status = .expired
                    task.scheduledTime = nil
                    task.scheduledEndTime = nil
                    decisions.append(.init(taskID: task.id, action: .expired, reason: "reaper_on_defer"))
                    changed.insert(task.id)
                    byID[task.id] = task
                    continue
                case .alive:
                    break
                }

                task.applyTimeConstraint(.fluid)
                applyStart(placement.start, to: &task, on: placement.day, calendar: calendar)
                task.scheduledDate = placement.day
                decisions.append(.init(
                    taskID: task.id,
                    action: .deferNextGap,
                    reason: "deferred_next_gap"
                ))
                changed.insert(task.id)
                byID[task.id] = task
                continue
            }

            // Stage 5: park + recovery queue (fluid / flexible only).
            // True anchored immovables keep their clock when no shift path exists.
            if task.timeConstraintValue == .anchored {
                blocked.append(interval)
                blocked.sort { $0.start < $1.start }
                decisions.append(.init(taskID: task.id, action: .keep, reason: "anchored_overlap_preserved"))
                byID[task.id] = task
                continue
            }

            task.scheduledTime = nil
            task.scheduledEndTime = nil
            task.applyTimeConstraint(.fluid)
            parkedQueue?.enqueue(from: task, reason: "cascade_park", now: now)
            parkedIDs.append(task.id)
            decisions.append(.init(taskID: task.id, action: .park, reason: "parked_to_recovery_queue"))
            changed.insert(task.id)
            byID[task.id] = task
        }

        let merged = tasks.map { byID[$0.id] ?? $0 }
        let recoveryLock = merged.contains { $0.tags.contains("recovery-block") || $0.tags.contains("brain-locked") }
        return ConflictCascadeResult(
            tasks: merged,
            decisions: decisions,
            changedTaskIDs: changed,
            unresolvedTaskIDs: [],
            parkedTaskIDs: parkedIDs,
            triggeredRecoveryLock: recoveryLock
        )
    }

    // MARK: - Ranking

    /// Higher wins the slot. Pure function of constraint + commitments + priority.
    public static func rank(_ task: LifeTask) -> Int {
        var score = 0
        switch task.timeConstraintValue {
        case .anchored: score += 100
        case .flexible: score += 50
        case .fluid: score += 10
        }
        if task.isLifeCommitmentTask { score += 20 }
        if task.isFixedTimeEvent { score += 15 }
        switch task.priority {
        case .critical: score += 10
        case .high: score += 8
        case .medium: score += 4
        case .low: score += 2
        case .someday: score += 0
        }
        return score
    }

    public static func canMove(_ task: LifeTask) -> Bool {
        // Meals always yield to anchored commitments — even when user-placed.
        if OnboardingTaskSeeder.isMealRoutineTitle(task.title) { return true }
        if TaskConstraintAlignment.isUserPlaced(task) { return false }
        if task.isLifeCommitmentTask, task.timeConstraintValue == .anchored { return false }
        if task.timeConstraintValue == .anchored { return false }
        switch task.timeConstraintValue {
        case .anchored:
            return false
        case .flexible, .fluid:
            return true
        }
    }

    public static func canCompress(_ task: LifeTask) -> Bool {
        guard task.timeConstraintValue != .anchored else { return false }
        // Never compress below semantic / explicit viable floor.
        return task.estimatedMinutes > task.minimumViableDurationValue
    }

    public static func canDefer(_ task: LifeTask) -> Bool {
        task.timeConstraintValue == .fluid
            || (task.timeConstraintValue == .flexible && !task.isLifeCommitmentTask)
    }

    /// Next open gap within `horizonDays` after `from`.
    /// Blockers are expanded by `bufferMinutes` so new placements never kiss anchored edges.
    public static func findNextAvailableGap(
        durationMinutes: Int,
        from dayStart: Date,
        excludingTaskID: String,
        universe: [LifeTask],
        horizonDays: Int = deferralHorizonDays,
        bufferMinutes: Int = placementBufferMinutes,
        calendar: Calendar = .current
    ) -> (day: Date, start: Date)? {
        let buf = TimeInterval(bufferMinutes * 60)
        for offset in 1...max(horizonDays, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let dayAnchor = calendar.startOfDay(for: day)
            let rawBlocked = TaskScheduleInterval.intervals(
                from: universe.filter { $0.id != excludingTaskID && $0.scheduledTime != nil },
                on: dayAnchor,
                calendar: calendar
            )
            // Buffer-anchor: treat each blocker as larger so we don't pack back-to-back.
            let blocked = rawBlocked.map {
                TaskScheduleInterval(
                    taskID: $0.taskID,
                    start: $0.start.addingTimeInterval(-buf),
                    end: $0.end.addingTimeInterval(buf)
                )
            }
            let dayBegin = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: dayAnchor) ?? dayAnchor
            if let open = findOpenStart(
                durationMinutes: durationMinutes,
                blocked: blocked,
                after: dayBegin,
                dayStart: dayAnchor,
                bufferMinutes: bufferMinutes,
                calendar: calendar
            ) {
                return (dayAnchor, open)
            }
        }
        return nil
    }

    /// Resolve personal compress floors from Behavioral Vault signatures (optional).
    public static func vaultFloors(
        from signatures: [BehavioralSignature],
        defaultDeepWorkFloor: Int = 45
    ) -> [String: Int] {
        var map: [String: Int] = [:]
        for sig in signatures {
            // Higher confidence in flexible/fluid deep-work style → allow slightly lower floors.
            guard sig.meanConfidence >= 0.55 else { continue }
            if sig.semanticHash.contains("deepwork") || sig.semanticHash.contains("creative") {
                let floor = sig.learnedConstraint == .fluid ? 30 : defaultDeepWorkFloor
                map[sig.semanticHash] = floor
            }
            if sig.semanticHash.contains("physical") || sig.semanticHash.contains("gym") {
                map[sig.semanticHash] = sig.learnedConstraint == .fluid ? 25 : 30
            }
        }
        return map
    }

    // MARK: - Slot search

    private static func isActiveOnDay(_ task: LifeTask, day: Date, calendar: Calendar) -> Bool {
        guard task.status.isActive, task.scheduledTime != nil, let scheduledDate = task.scheduledDate else {
            return false
        }
        return calendar.isDate(scheduledDate, inSameDayAs: day)
    }

    private static func applyStart(
        _ start: Date,
        to task: inout LifeTask,
        on day: Date,
        calendar: Calendar
    ) {
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: start)
        var dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        dayParts.hour = timeOfDay.hour
        dayParts.minute = timeOfDay.minute
        dayParts.second = timeOfDay.second ?? 0
        let combined = calendar.date(from: dayParts) ?? start
        task.scheduledDate = day
        task.scheduledTime = combined
        task.scheduledEndTime = combined.addingTimeInterval(TimeInterval(duration * 60))
        task.updatedAt = Date()
    }

    private static func findOpenStart(
        durationMinutes: Int,
        blocked: [TaskScheduleInterval],
        after preferred: Date,
        dayStart: Date,
        bufferMinutes: Int,
        calendar: Calendar
    ) -> Date? {
        let dayEnd = calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(21 * 3600)
        var candidate = preferred
        // Also try from earliest blocker end if preferred is deadlocked.
        let starts = [preferred] + blocked.map {
            $0.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
        }
        for seed in starts {
            candidate = max(seed, preferred)
            for _ in 0..<96 {
                let probeEnd = candidate.addingTimeInterval(TimeInterval(durationMinutes * 60))
                if probeEnd > dayEnd { break }
                let overlaps = blocked.contains {
                    candidate < $0.end && $0.start < probeEnd
                }
                if !overlaps { return candidate }
                if let next = blocked.first(where: { candidate < $0.end && $0.start < probeEnd }) {
                    candidate = next.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
                } else {
                    candidate = calendar.date(byAdding: .minute, value: 15, to: candidate) ?? candidate
                }
            }
        }
        return nil
    }

    private static func findCompressibleGap(
        preferredStart: Date,
        minMinutes: Int,
        preferredMinutes: Int,
        blocked: [TaskScheduleInterval],
        dayStart: Date,
        bufferMinutes: Int,
        calendar: Calendar
    ) -> (start: Date, minutes: Int)? {
        let dayEnd = calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(21 * 3600)
        let sorted = blocked.sorted { $0.start < $1.start }
        var cursor = preferredStart
        // Probe gaps between blockers.
        var edges: [Date] = [preferredStart]
        edges.append(contentsOf: sorted.map {
            $0.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
        })
        for start in edges {
            cursor = start
            let nextBlockStart = sorted.first(where: { $0.start > cursor })?.start ?? dayEnd
            let available = Int(nextBlockStart.timeIntervalSince(cursor) / 60) - bufferMinutes
            guard available >= minMinutes else { continue }
            let minutes = min(preferredMinutes, available)
            let probeEnd = cursor.addingTimeInterval(TimeInterval(minutes * 60))
            let overlaps = sorted.contains { cursor < $0.end && $0.start < probeEnd }
            if !overlaps {
                return (cursor, minutes)
            }
        }
        return nil
    }
}
