import Foundation
import LookAfterAI
import LookAfterCore
import LookAfterData

/// AI-informed slot assignment for unslotted flexible/fluid tasks — falls back to `DaySlotAllocator`.
public enum AIScheduleSlotService {

    public struct DayContext: Sendable {
        public let day: Date
        public let allTasks: [LifeTask]
        public let unslotted: [LifeTask]
        public let model: LifeModel?
        public let healthContext: String?
        public let now: Date

        public init(
            day: Date,
            allTasks: [LifeTask],
            unslotted: [LifeTask],
            model: LifeModel? = LifeModelStore.load(),
            healthContext: String? = nil,
            now: Date = Date()
        ) {
            self.day = day
            self.allTasks = allTasks
            self.unslotted = unslotted
            self.model = model
            self.healthContext = healthContext
            self.now = now
        }
    }

    /// Returns validated suggestions — AI when available, otherwise local allocator.
    @MainActor
    public static func suggestSlots(
        for context: DayContext,
        glm: GLMService = .shared,
        calendar: Calendar = .current
    ) async -> [DayScheduleSuggestion] {
        let movableIDs = Set(context.unslotted.filter(\.isSchedulerMovable).map(\.id))
        guard !movableIDs.isEmpty else { return [] }

        if let ai = await aiSuggestions(for: context, movableIDs: movableIDs, glm: glm, calendar: calendar),
           !ai.isEmpty {
            let covered = Set(ai.map(\.id))
            let remainder = movableIDs.subtracting(covered)
            if remainder.isEmpty { return ai }
            let local = buildLocalSuggestions(
                for: Array(remainder),
                context: context,
                calendar: calendar
            )
            return ai + local
        }

        return buildLocalSuggestions(for: Array(movableIDs), context: context, calendar: calendar)
    }

    /// Applies suggestions to tasks — preserves flexible/fluid constraints (does not anchor).
    public static func applySuggestions(
        _ suggestions: [DayScheduleSuggestion],
        to tasks: inout [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> Set<String> {
        let dayStart = calendar.startOfDay(for: day)
        var changed = Set<String>()
        let byID = Dictionary.uniquingFirstValue(suggestions.map { ($0.id, $0) })

        for index in tasks.indices {
            guard let suggestion = byID[tasks[index].id] else { continue }
            guard tasks[index].isSchedulerMovable else { continue }

            guard let start = calendar.date(
                bySettingHour: suggestion.startHour,
                minute: suggestion.startMinute,
                second: 0,
                of: dayStart
            ) else { continue }

            let duration = max(tasks[index].estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            let end = start.addingTimeInterval(TimeInterval(duration * 60))

            var updated = tasks[index]
            updated.scheduledDate = dayStart
            updated.scheduledTime = start
            updated.scheduledEndTime = end
            updated.updatedAt = Date()
            if updated.timeConstraintValue == .anchored {
                // Auto-assign never flips user anchors; skip mutation.
                continue
            }
            tasks[index] = updated
            changed.insert(updated.id)
        }
        return changed
    }

    // MARK: - Private

    private static func aiSuggestions(
        for context: DayContext,
        movableIDs: Set<String>,
        glm: GLMService,
        calendar: Calendar
    ) async -> [DayScheduleSuggestion]? {
        do {
            let tier: AIModelTier = TaskManagementPreferences.highQualitySchedulingEnabled ? .premium : .standard
            let response = try await glm.complete(
                prompt: schedulingPrompt(for: context, calendar: calendar),
                systemPrompt: LookAfterPrompts.dailySchedulerSystem,
                tier: tier
            )
            let decoded = try decodeSuggestions(from: response)
            let validated = DayScheduleSuggestionValidator.validated(decoded, allowedTaskIDs: movableIDs)
            return validated.isEmpty ? nil : validated
        } catch {
            return nil
        }
    }

    private static func schedulingPrompt(for context: DayContext, calendar: Calendar) -> String {
        let profile = UserLifeProfileStore.load()
        let supplemental = PlanningPromptContextBuilder.supplementalContextBlock(
            analytics: nil,
            includeCalibration: true
        )
        let dayStart = calendar.startOfDay(for: context.day)
        let slotted = context.allTasks.filter { task in
            guard task.status.isActive, let scheduledDate = task.scheduledDate, task.scheduledTime != nil else {
                return false
            }
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
                && TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: dayStart, calendar: calendar)
        }
        let fixed = slotted.filter { !$0.isSchedulerMovable || $0.isFixedTimeEvent || $0.isLifeCommitmentTask }
        let movable = context.unslotted.filter(\.isSchedulerMovable)
        let analyticsBlock = context.healthContext.map { "\($0)\n" } ?? ""

        return """
        AUTO-ASSIGN FLEXIBLE SLOTS (silent background reconcile — no user preview)
        \(PlanningPromptContextBuilder.temporalBlock(now: context.now, profile: profile, planningDay: context.day))
        \(PlanningPromptContextBuilder.schedulingRulesBlock(planningDay: context.day))
        \(PlanningPromptContextBuilder.dailyRoutineBlock())
        \(PlanningPromptContextBuilder.sleepBoundaryBlock(now: context.now, profile: profile))
        \(PlanningPromptContextBuilder.combinedLifeContextBlock(profile: profile))
        \(supplemental.isEmpty ? "" : "\(supplemental)\n")
        \(analyticsBlock)
        \(PlanningPromptContextBuilder.medicationsBlock(MedicationStore.load()))
        \(PlanningPromptContextBuilder.tasksBlock(fixed, style: .schedulingFixed))
        \(PlanningPromptContextBuilder.tasksBlock(movable, style: .schedulingFlexible))

        Return ONLY a JSON array matching this schema (use actual UNSLOTTED task ids):
        \(PlanningPromptContextBuilder.dailySchedulerResponseSchema)
        Include an entry for every UNSLOTTED task id listed above. Omit already-slotted and fixed ids.
        Never assign the same startHour/startMinute to two tasks. Stagger with 5+ minute gaps.
        """
    }

    private static func buildLocalSuggestions(
        for ids: [String],
        context: DayContext,
        calendar: Calendar
    ) -> [DayScheduleSuggestion] {
        let profile = UserLifeProfileStore.load()
        let dayStart = calendar.startOfDay(for: context.day)
        let taskByID = Dictionary.uniquingFirstValue(context.allTasks.map { ($0.id, $0) })
        let windows = SchedulingWindows.from(profile: profile, lifeModel: context.model)

        let requests = ids.compactMap { id -> DaySlotAllocator.Request? in
            guard let task = taskByID[id], task.isSchedulerMovable else { return nil }
            return DaySlotAllocator.Request(
                id: id,
                estimatedMinutes: max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes),
                priority: task.priority,
                preferredStart: RoutineScheduleAnchorResolver.preferredStart(
                    for: task,
                    on: dayStart,
                    model: context.model,
                    profile: profile,
                    calendar: calendar
                )
            )
        }

        let occupied = context.allTasks.filter { task in
            guard task.status.isActive, let scheduledDate = task.scheduledDate, task.scheduledTime != nil else {
                return false
            }
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }

        let allocations = DaySlotAllocator.allocateAcrossWindows(
            requests: requests,
            existingTasks: occupied,
            windows: windows,
            on: dayStart,
            now: context.now,
            calendar: calendar
        )

        return allocations.map { allocation in
            let components = PlanningSchedulePolicy.components(from: allocation.scheduledTime, calendar: calendar)
            return DayScheduleSuggestion(
                id: allocation.id,
                startHour: components.hour,
                startMinute: components.minute,
                reason: "Prioritized around fixed blocks and urgency"
            )
        }
    }

    private static func decodeSuggestions(from response: String) throws -> [DayScheduleSuggestion] {
        let clean = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try SharedFormatters.jsonDecoderSeconds.decode([RawScheduleSuggestion].self, from: Data(clean.utf8))
        return decoded.map {
            DayScheduleSuggestion(
                id: $0.id,
                startHour: $0.startHour,
                startMinute: $0.startMinute,
                reason: $0.reason ?? ""
            )
        }
    }
}

private struct RawScheduleSuggestion: Decodable {
    let id: String
    let startHour: Int
    let startMinute: Int
    let reason: String?
}
