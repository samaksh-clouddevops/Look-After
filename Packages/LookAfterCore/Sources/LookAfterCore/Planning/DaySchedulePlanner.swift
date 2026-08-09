import Foundation

/// Single schedule engine — plan → diff → apply (behind `SchedulePlannerFlags.useUnifiedDayPlanner`).
public enum DaySchedulePlanner {

    public struct PlannedSlot: Sendable, Equatable {
        public let taskID: String
        public let start: Date
        public let end: Date
    }

    public struct PlanResult: Sendable {
        public var slots: [PlannedSlot]
        public var changedTaskIDs: Set<String>

        public init(slots: [PlannedSlot] = [], changedTaskIDs: Set<String> = []) {
            self.slots = slots
            self.changedTaskIDs = changedTaskIDs
        }
    }

    private static let diffThresholdSeconds: TimeInterval = 15 * 60

    /// Computes the ideal same-day schedule without persisting.
    public static func plan(
        tasks: [LifeTask],
        on day: Date,
        model: LifeModel? = LifeModelStore.load(),
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        structure: DayStructure? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PlanResult {
        let dayStart = calendar.startOfDay(for: day)
        let compiled = structure ?? DayStructureCompiler.compile(profile: profile, model: model, calendar: calendar)
        var slots: [PlannedSlot] = []
        var occupied: [TaskScheduleInterval] = []

        let active = tasks.filter { task in
            guard task.status.isActive else { return false }
            guard let scheduledDate = task.scheduledDate else {
                return calendar.isDateInToday(day) && task.scheduledTime == nil
            }
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }

        // Phase 1 — snap anchored / user-placed / structure-backed tasks.
        for task in active {
            if TaskConstraintAlignment.isUserPlaced(task),
               let start = task.scheduledTime,
               calendar.isDate(start, inSameDayAs: dayStart) {
                let end = task.scheduledEndTime ?? start.addingTimeInterval(TimeInterval(max(task.estimatedMinutes, 15) * 60))
                appendSlot(taskID: task.id, start: start, end: end, to: &slots, occupied: &occupied)
                continue
            }

            if let anchor = compiled.anchor(matching: task), anchor.treatAsFixed,
               let start = anchor.start(on: dayStart, calendar: calendar) {
                let end = start.addingTimeInterval(TimeInterval(anchor.durationMinutes * 60))
                appendSlot(taskID: task.id, start: start, end: end, to: &slots, occupied: &occupied)
                continue
            }

            if let resolved = RoutineScheduleAnchorResolver.resolve(
                for: task,
                on: dayStart,
                model: model,
                profile: profile,
                calendar: calendar
            ), resolved.treatAsFixed {
                appendSlot(taskID: task.id, start: resolved.start, end: resolved.end, to: &slots, occupied: &occupied)
            } else if let resolved = RoutineScheduleAnchorResolver.resolve(
                for: task,
                on: dayStart,
                model: model,
                profile: profile,
                calendar: calendar
            ), OnboardingTaskSeeder.isMealRoutineTitle(task.title) {
                // Preferred meal anchor — include for cascade even when it overlaps a fixed block.
                appendSlot(
                    taskID: task.id,
                    start: resolved.start,
                    end: resolved.end,
                    to: &slots,
                    occupied: &occupied,
                    allowOverlap: true
                )
            }
        }

        // Phase 2 — allocate remaining movable tasks with preferred starts.
        let slottedIDs = Set(slots.map(\.taskID))
        let remaining = active.filter { !slottedIDs.contains($0.id) && $0.isSchedulerMovable }
        let windows = SchedulingWindows.from(profile: profile, lifeModel: model)
        let requests = remaining.map { task in
            DaySlotAllocator.Request(
                id: task.id,
                estimatedMinutes: max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes),
                priority: task.priority,
                preferredStart: RoutineScheduleAnchorResolver.preferredStart(
                    for: task,
                    on: dayStart,
                    model: model,
                    profile: profile,
                    calendar: calendar
                )
            )
        }

        let existingTasks = tasks.filter { task in
            slots.contains { $0.taskID == task.id }
        }
        let allocations = DaySlotAllocator.allocateAcrossWindows(
            requests: requests,
            existingTasks: existingTasks,
            windows: windows,
            on: dayStart,
            now: now,
            calendar: calendar
        )

        for allocation in allocations {
            guard let task = remaining.first(where: { $0.id == allocation.id }) else { continue }
            let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            let end = allocation.scheduledTime.addingTimeInterval(TimeInterval(duration * 60))
            appendSlot(taskID: task.id, start: allocation.scheduledTime, end: end, to: &slots, occupied: &occupied)
        }

        // Phase 3 — resolve overlaps via cascade on synthetic task set.
        var synthetic = active
        for slot in slots {
            guard let index = synthetic.firstIndex(where: { $0.id == slot.taskID }) else { continue }
            synthetic[index].scheduledDate = dayStart
            synthetic[index].scheduledTime = slot.start
            synthetic[index].scheduledEndTime = slot.end
        }

        let cascade = ConflictResolutionCascade.resolve(
            tasks: synthetic.filter { $0.scheduledTime != nil },
            on: dayStart,
            model: model,
            now: now,
            calendar: calendar
        )

        slots = cascade.tasks.compactMap { task in
            guard let start = task.scheduledTime else { return nil }
            let end = task.scheduledEndTime ?? start.addingTimeInterval(TimeInterval(max(task.estimatedMinutes, 15) * 60))
            return PlannedSlot(taskID: task.id, start: start, end: end)
        }

        let changed = diffChangedIDs(tasks: active, slots: slots, calendar: calendar)
        return PlanResult(slots: slots.sorted { $0.start < $1.start }, changedTaskIDs: changed)
    }

    /// Applies plan diff to tasks — mutates when delta exceeds threshold or slot removes overlap.
    public static func apply(
        plan: PlanResult,
        to tasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> (tasks: [LifeTask], changedIDs: Set<String>) {
        var byID = Dictionary.uniquingFirstValue(tasks.map { ($0.id, $0) })
        var changed = Set<String>()
        let dayStart = calendar.startOfDay(for: day)

        for slot in plan.slots {
            guard var task = byID[slot.taskID] else { continue }
            let current = task.scheduledTime
            let resolvesOverlap = slotResolvesOverlap(
                for: task,
                slot: slot,
                among: Array(byID.values),
                on: dayStart,
                calendar: calendar
            )
            if let current, !resolvesOverlap,
               abs(current.timeIntervalSince(slot.start)) < diffThresholdSeconds,
               task.scheduledEndTime.map({ abs($0.timeIntervalSince(slot.end)) < diffThresholdSeconds }) ?? false {
                continue
            }
            task.scheduledDate = dayStart
            task.scheduledTime = slot.start
            task.scheduledEndTime = slot.end
            task = TaskConstraintAlignment.align(task)
            task.updatedAt = Date()
            byID[slot.taskID] = task
            changed.insert(slot.taskID)
        }

        let merged = tasks.map { byID[$0.id] ?? $0 }
        return (merged, changed)
    }

    /// True when applying the planned slot removes an overlap the task currently has.
    private static func slotResolvesOverlap(
        for task: LifeTask,
        slot: PlannedSlot,
        among tasks: [LifeTask],
        on dayStart: Date,
        calendar: Calendar
    ) -> Bool {
        guard let currentWindow = TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) else {
            return false
        }
        let others = tasks.filter { $0.id != task.id && $0.status.isActive }
        let currentlyOverlaps = TaskScheduleInterval.intervals(from: others, on: dayStart, calendar: calendar)
            .contains { currentWindow.overlaps($0) }
        guard currentlyOverlaps else { return false }

        var candidate = task
        candidate.scheduledDate = dayStart
        candidate.scheduledTime = slot.start
        candidate.scheduledEndTime = slot.end
        guard let candidateWindow = TaskScheduleInterval.window(for: candidate, on: dayStart, calendar: calendar) else {
            return false
        }
        return !TaskScheduleInterval.intervals(from: others, on: dayStart, calendar: calendar)
            .contains { candidateWindow.overlaps($0) }
    }

    private static func appendSlot(
        taskID: String,
        start: Date,
        end: Date,
        to slots: inout [PlannedSlot],
        occupied: inout [TaskScheduleInterval],
        allowOverlap: Bool = false
    ) {
        let interval = TaskScheduleInterval(taskID: taskID, start: start, end: end)
        if !allowOverlap, occupied.contains(where: { interval.overlaps($0) }) { return }
        if let existingIndex = slots.firstIndex(where: { $0.taskID == taskID }) {
            slots[existingIndex] = PlannedSlot(taskID: taskID, start: start, end: end)
        } else {
            slots.append(PlannedSlot(taskID: taskID, start: start, end: end))
        }
        if !allowOverlap {
            occupied.append(interval)
            occupied.sort { $0.start < $1.start }
        }
    }

    private static func diffChangedIDs(
        tasks: [LifeTask],
        slots: [PlannedSlot],
        calendar: Calendar
    ) -> Set<String> {
        var changed = Set<String>()
        let slotByID = Dictionary.uniquingFirstValue(slots.map { ($0.taskID, $0) })
        for task in tasks {
            guard let slot = slotByID[task.id] else { continue }
            guard let current = task.scheduledTime else {
                changed.insert(task.id)
                continue
            }
            if abs(current.timeIntervalSince(slot.start)) >= diffThresholdSeconds {
                changed.insert(task.id)
            }
        }
        return changed
    }
}
