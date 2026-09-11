import Foundation
import LookAfterCore

/// Result of filling an unexpected calendar gap.
public enum GapFillResult: Sendable, Equatable {
    case recoveryLocked(LifeTask)
    case resurrected([ParkedTaskEntry])
    case nothing
}

/// App-facing recovery — decay, energy-aware bidding, someday vault, briefing aggregation.
@MainActor
public final class ParkedTaskRecoveryService {
    public static let shared = ParkedTaskRecoveryService()

    private let store: ParkedTaskQueueStore
    private let someday: SomedayVaultStore
    private let resurrected: ResurrectedTaskRegistry

    public init(
        store: ParkedTaskQueueStore = .shared,
        someday: SomedayVaultStore = .shared,
        resurrected: ResurrectedTaskRegistry = .shared
    ) {
        self.store = store
        self.someday = someday
        self.resurrected = resurrected
    }

    @discardableResult
    public func runDecayPass(now: Date = Date()) -> (decayed: [ParkedTaskEntry], discarded: [String]) {
        store.applyFluidDecay(now: now)
    }

    public func recoverable(limit: Int = 5) -> [ParkedTaskEntry] {
        store.candidatesForReintegration(limit: limit)
    }

    public func decayedNeedingReview() -> [ParkedTaskEntry] {
        store.snapshot().decayedEntries
    }

    /// Unexpected free block — energy/TOD aware; may lock a recovery block instead.
    /// When `tasksVM` is provided, winners are written into the operational timeline.
    public func auction(
        gapMinutes: Int,
        energy: EnergyLevel = .moderate,
        consecutiveHighLoadDays: Int = 0,
        gapStart: Date? = nil,
        day: Date = Date(),
        userId: String = "",
        now: Date = Date(),
        limit: Int = 3,
        tasksVM: TasksViewModel? = nil,
        sabotagePolicy: SabotagePolicyStore = .shared
    ) -> GapFillResult {
        let coolingDown = sabotagePolicy.isCoolingDown(now: now)

        let outcome = store.bidForGap(
            gapMinutes: gapMinutes,
            energy: energy,
            consecutiveHighLoadDays: consecutiveHighLoadDays,
            sabotageCooldownActive: coolingDown,
            now: now,
            limit: limit
        )

        switch outcome {
        case .sabotageRecovery:
            guard !coolingDown else { return .nothing }
            let start = gapStart ?? now
            let block = GapAuctionEngine.makeRecoveryBlock(
                gapStart: start,
                gapMinutes: gapMinutes,
                day: day,
                userId: userId
            )
            tasksVM?.createTask(block)
            CascadeActionLog.shared.record(
                result: ConflictCascadeResult(
                    tasks: [block],
                    decisions: [
                        .init(taskID: block.id, action: .keep, reason: "sabotage_recovery")
                    ],
                    triggeredRecoveryLock: true
                ),
                recoveryDurationMinutes: gapMinutes,
                now: now
            )
            return .recoveryLocked(block)

        case .filled(let winners):
            let placed = placeWinners(
                winners,
                gapStart: gapStart ?? now,
                day: day,
                userId: userId,
                tasksVM: tasksVM,
                now: now
            )
            resurrected.mark(placed.map(\.taskID), now: now)
            if !placed.isEmpty {
                CascadeActionLog.shared.record(
                    result: ConflictCascadeResult(tasks: [], decisions: []),
                    resurrectedCount: placed.count,
                    now: now
                )
            }
            return placed.isEmpty ? .nothing : .resurrected(placed)

        case .empty:
            // Sabotage may still be warranted when pool empty but streak high.
            if !coolingDown, consecutiveHighLoadDays >= 5, gapMinutes >= 45, gapMinutes <= 180 {
                let start = gapStart ?? now
                let block = GapAuctionEngine.makeRecoveryBlock(
                    gapStart: start,
                    gapMinutes: gapMinutes,
                    day: day,
                    userId: userId
                )
                tasksVM?.createTask(block)
                CascadeActionLog.shared.record(
                    result: ConflictCascadeResult(
                        tasks: [block],
                        decisions: [
                            .init(taskID: block.id, action: .keep, reason: "sabotage_recovery")
                        ],
                        triggeredRecoveryLock: true
                    ),
                    recoveryDurationMinutes: gapMinutes,
                    now: now
                )
                return .recoveryLocked(block)
            }
            return .nothing
        }
    }

    /// Pull parked winners into LifeState on the freed gap (sparkle + real schedule).
    @discardableResult
    public func placeSelected(
        _ winners: [ParkedTaskEntry],
        gapStart: Date,
        day: Date,
        userId: String,
        tasksVM: TasksViewModel?,
        now: Date = Date()
    ) -> [ParkedTaskEntry] {
        placeWinners(winners, gapStart: gapStart, day: day, userId: userId, tasksVM: tasksVM, now: now)
    }

    /// Pull parked winners into LifeState on the freed gap (sparkle + real schedule).
    @discardableResult
    private func placeWinners(
        _ winners: [ParkedTaskEntry],
        gapStart: Date,
        day: Date,
        userId: String,
        tasksVM: TasksViewModel?,
        now: Date
    ) -> [ParkedTaskEntry] {
        guard let tasksVM else {
            // No writer — still sparkle IDs for UI if tasks already exist.
            return winners
        }
        var cursor = gapStart
        var placed: [ParkedTaskEntry] = []
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)

        for entry in winners {
            var task = tasksVM.tasks.first(where: { $0.id == entry.taskID })
            let duration = max(entry.originalDurationMinutes, TaskDurationPolicy.minimumMinutes)
            let end = cursor.addingTimeInterval(TimeInterval(duration * 60))

            if var existing = task {
                existing.scheduledDate = dayStart
                existing.scheduledTime = cursor
                existing.scheduledEndTime = end
                existing.estimatedMinutes = duration
                existing.applyTimeConstraint(.fluid)
                existing.status = .pending
                existing.updatedAt = now
                tasksVM.updateTask(existing)
                _ = store.dequeue(taskID: entry.taskID)
                placed.append(entry)
            } else {
                var created = LifeTask(
                    id: entry.taskID,
                    title: entry.title,
                    lifeArea: entry.lifeArea,
                    priority: entry.priority,
                    status: .pending,
                    estimatedMinutes: duration,
                    scheduledDate: dayStart,
                    scheduledTime: cursor,
                    timeConstraint: .fluid,
                    scheduledEndTime: end,
                    userId: userId
                )
                created.updatedAt = now
                tasksVM.createTask(created)
                _ = store.dequeue(taskID: entry.taskID)
                placed.append(entry)
            }
            cursor = end.addingTimeInterval(TimeInterval(ConflictResolutionCascade.defaultBufferMinutes * 60))
        }
        if !placed.isEmpty, !userId.isEmpty {
            tasksVM.requestDebouncedScheduleReconcile(userId: userId, immediate: true)
        }
        return placed
    }

    /// User deleted a recovery block — emit sabotage override + 7-day cool-down.
    public func handleRecoveryBlockOverride(
        task: LifeTask,
        sabotagePolicy: SabotagePolicyStore = .shared,
        now: Date = Date()
    ) {
        guard task.tags.contains("recovery-block") || task.tags.contains("brain-locked") else { return }
        sabotagePolicy.recordSabotageOverride(now: now)
        InteractionTelemetryService.shared.recordConstraintChange(
            taskID: task.id,
            taskTitle: "recovery_block",
            semanticType: "recovery",
            from: .anchored,
            to: .fluid,
            source: .sabotageOverride
        )
        CascadeActionLog.shared.record(
            result: ConflictCascadeResult(
                tasks: [],
                decisions: [
                    .init(taskID: task.id, action: .park, reason: "sabotage_override_by_user")
                ]
            ),
            now: now
        )
    }

    public func markSomeday(taskID: String) {
        if let entry = store.snapshot().entries.first(where: { $0.taskID == taskID }) {
            someday.add(from: entry)
        }
        store.markSomeday(taskID: taskID)
        _ = store.dequeue(taskID: taskID)
    }

    public func bulkSomeday(taskIDs: [String]) {
        taskIDs.forEach(markSomeday)
    }

    public func markDiscarded(taskID: String) {
        store.markDiscarded(taskID: taskID)
        _ = store.dequeue(taskID: taskID)
    }

    public func bulkDiscard(taskIDs: [String]) {
        taskIDs.forEach(markDiscarded)
    }

    public func reclaim(taskID: String) -> ParkedTaskEntry? {
        store.dequeue(taskID: taskID)
    }

    public func isResurrected(_ taskID: String) -> Bool {
        resurrected.isResurrected(taskID)
    }

    public func resurrectedIDs() -> Set<String> {
        resurrected.activeIDs()
    }

    public var somedayCount: Int { someday.count }

    /// Briefing lines — aggregate decay; never list 10 individual guilt items.
    public func briefingNotes(now: Date = Date()) -> [String] {
        _ = runDecayPass(now: now)
        var lines: [String] = []

        let recoverable = store.candidatesForReintegration(limit: 3)
        if !recoverable.isEmpty {
            let names = recoverable.map(\.title).joined(separator: ", ")
            lines.append("Waiting room: \(names). Say the word and I’ll slot them back.")
        }

        let decayed = store.snapshot().decayedEntries
        if decayed.count == 1, let only = decayed.first {
            lines.append(
                "“\(only.title)” has been parked over two weeks. Keep as someday, or let it go?"
            )
        } else if decayed.count > 1 {
            // Single bulk prompt — keep briefing clean.
            lines.append(
                "You have \(decayed.count) tasks parked for two weeks. Review or bulk-discard when ready."
            )
        }

        return lines
    }
}
