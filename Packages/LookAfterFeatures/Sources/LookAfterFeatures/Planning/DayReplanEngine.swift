import Foundation
import LookAfterCore
import LookAfterAI

// MARK: - Context

public enum DayReplanTrigger: String, Sendable, Equatable {
    case generic
    case postWake
    case goingOut
    case freedSlot
    case calendarChange
    case badDay
    case recoveryDay
    case travelDisruption
}

public struct DayReplanAwayWindow: Sendable, Equatable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct DayReplanContext: Sendable {
    public var planningContext: PlanningConversationContext
    public var completedTasks: [LifeTask]
    public var weatherSummary: String?
    public var sleepHours: Double?
    public var locationLabel: String?
    public var userGoals: String?
    public var trigger: DayReplanTrigger
    public var activeConstraint: UserDayConstraint?
    public var missedTasks: [LifeTask]
    public var awayWindow: DayReplanAwayWindow?
    public var minutesLate: Int?
    /// Time window opened by removing a task from today's timeline.
    public var freedSlotWindow: DayReplanAwayWindow?
    public var removedTaskTitle: String?

    public init(
        planningContext: PlanningConversationContext,
        completedTasks: [LifeTask],
        weatherSummary: String? = nil,
        sleepHours: Double? = nil,
        locationLabel: String? = nil,
        userGoals: String? = nil,
        trigger: DayReplanTrigger = .generic,
        activeConstraint: UserDayConstraint? = nil,
        missedTasks: [LifeTask] = [],
        awayWindow: DayReplanAwayWindow? = nil,
        minutesLate: Int? = nil,
        freedSlotWindow: DayReplanAwayWindow? = nil,
        removedTaskTitle: String? = nil
    ) {
        self.planningContext = planningContext
        self.completedTasks = completedTasks
        self.weatherSummary = weatherSummary
        self.sleepHours = sleepHours
        self.locationLabel = locationLabel
        self.userGoals = userGoals
        self.trigger = trigger
        self.activeConstraint = activeConstraint
        self.missedTasks = missedTasks
        self.awayWindow = awayWindow
        self.minutesLate = minutesLate
        self.freedSlotWindow = freedSlotWindow
        self.removedTaskTitle = removedTaskTitle
    }
}

public struct DayReplanScheduleChange: Sendable, Equatable, Codable {
    public var taskID: String
    public var startHour: Int?
    public var startMinute: Int?
    public var deferToTomorrow: Bool
    public var reason: String

    public init(taskID: String, startHour: Int? = nil, startMinute: Int? = nil, deferToTomorrow: Bool = false, reason: String = "") {
        self.taskID = taskID
        self.startHour = startHour
        self.startMinute = startMinute
        self.deferToTomorrow = deferToTomorrow
        self.reason = reason
    }
}

public struct DayReplanResult: Sendable {
    public var summary: String
    public var scheduleChanges: [DayReplanScheduleChange]
    public var mutations: [PlanMutation]
    public var timelineDeltas: [PlanningTimelineDelta]
    public var planVariants: [PlanVariant]?
    public var recommendedVariantID: String?

    public init(
        summary: String,
        scheduleChanges: [DayReplanScheduleChange] = [],
        mutations: [PlanMutation] = [],
        timelineDeltas: [PlanningTimelineDelta] = [],
        planVariants: [PlanVariant]? = nil,
        recommendedVariantID: String? = nil
    ) {
        self.summary = summary
        self.scheduleChanges = scheduleChanges
        self.mutations = mutations
        self.timelineDeltas = timelineDeltas
        self.planVariants = planVariants
        self.recommendedVariantID = recommendedVariantID
    }

    /// Effective changes for apply — selected variant or top-level scheduleChanges.
    public func effectiveChanges(selectedVariantID: String? = nil) -> [DayReplanScheduleChange] {
        if let id = selectedVariantID ?? recommendedVariantID,
           let variant = planVariants?.first(where: { $0.id == id }) {
            return variant.scheduleChanges
        }
        if let variants = planVariants, !variants.isEmpty, scheduleChanges.isEmpty {
            let recommended = variants.first(where: \.recommended) ?? variants[0]
            return recommended.scheduleChanges
        }
        return scheduleChanges
    }

    public func effectiveTimelineDeltas(selectedVariantID: String? = nil) -> [PlanningTimelineDelta] {
        if let id = selectedVariantID ?? recommendedVariantID,
           let variant = planVariants?.first(where: { $0.id == id }) {
            return variant.timelineDeltas
        }
        return timelineDeltas
    }
}

// MARK: - Engine

/// Reconsiders the remainder of the day from the current moment — lowest executive cost plan.
public final class DayReplanEngine {
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }

    public func replan(context: DayReplanContext) async throws -> DayReplanResult {
        let prompt = buildPrompt(context: context)
        let system = systemPrompt(for: context.trigger)

        let raw: String
        do {
            raw = try await glm.sendMessage(prompt, systemPrompt: system, history: [], tier: .premium)
        } catch {
            print("[DayReplan] AI unavailable: \(error.localizedDescription)")
            return localFallback(context: context)
        }
        return try decode(raw: raw, context: context)
    }

    private func systemPrompt(for trigger: DayReplanTrigger) -> String {
        var rules = """
        You are the Executive Brain replanning the REST of today from the current moment.
        Never use internal labels (Deep Work Block, Focus Block, Planning Block, Session 1).
        Communicate in human actions. Simulate multiple schedules mentally, pick lowest executive cost.
        Defer work to tomorrow when meetings or energy make it unrealistic — explain why in summary.
        Never invent medication times. Return ONLY valid JSON — no markdown fences.
        \(PlanningPromptContextBuilder.duplicateReuseRulesBlock())
        """
        switch trigger {
        case .postWake:
            rules += """

            POST-WAKE RULES:
            - Address EVERY missed task explicitly in scheduleChanges (deferToTomorrow or reschedule).
            - Prefer defer over stacking fake catch-up — guilt-free recovery.
            - Salvage only high-value missed items if they still fit before sleep boundary.
            """
        case .goingOut:
            rules += """

            GOING-OUT RULES:
            - Treat the AWAY WINDOW as hard busy time — never schedule movable work inside it.
            - Compress high-priority work before departure; defer overflow to after return or tomorrow.
            - Protect fixed commitments outside the away window when possible.
            """
        case .freedSlot:
            rules += """

            FREED-SLOT RULES:
            - User removed a task from today — only fill the FREED SLOT window with movable work.
            - Never move anchored/fixed commitments.
            - Do not reschedule tasks already placed outside the freed slot unless deferring to tomorrow.
            - Prefer one best-fit task; only pack multiple if combined duration fits inside the slot.
            """
        case .calendarChange:
            rules += """

            CALENDAR-CHANGE RULES:
            - A new or moved meeting was added — reshuffle movable tasks around it.
            - Never move anchored/fixed commitments or the new meeting itself.
            - Prefer minimal changes; explain each move in summary.
            - Defer overflow to tomorrow when the afternoon no longer fits.
            """
        case .badDay, .recoveryDay:
            rules += """

            BAD-DAY / RECOVERY RULES:
            - User is having a rough day — prioritize minimum viable plan.
            - Defer non-essential flexible work to tomorrow guilt-free.
            - Protect fixed commitments and one high-value task if possible.
            - Offer rest blocks; never stack catch-up.
            """
        case .travelDisruption:
            rules += """

            TRAVEL-DISRUPTION RULES:
            - Travel or flight change detected — protect departure buffer.
            - Defer tasks that conflict with travel window.
            - Compress pre-travel essentials only.
            """
        case .generic:
            break
        }
        return rules
    }

    private func buildPrompt(context: DayReplanContext) -> String {
        let pc = context.planningContext
        let profile = pc.lifeProfile
        let now = Date()

        let completed = context.completedTasks.map { "- \($0.title)" }.joined(separator: "\n")
        let supplemental = PlanningPromptContextBuilder.supplementalContextBlock(
            analytics: pc.analyticsContext,
            includeCalibration: true
        )

        var triggerBlocks = ""
        if context.trigger == .postWake, let wake = context.activeConstraint?.wakeTime {
            triggerBlocks += PlanningPromptContextBuilder.postWakeReplanBlock(
                wakeTime: wake,
                minutesLate: context.minutesLate
            ) + "\n"
        }
        if context.trigger == .goingOut,
           let departure = context.activeConstraint?.departureTime,
           let duration = context.activeConstraint?.durationMinutes,
           let end = context.awayWindow?.end {
            triggerBlocks += PlanningPromptContextBuilder.goingOutBlock(
                departure: departure,
                durationMinutes: duration,
                endTime: end
            ) + "\n"
        }
        if !context.missedTasks.isEmpty {
            triggerBlocks += PlanningPromptContextBuilder.missedTasksBlock(context.missedTasks) + "\n"
        }
        if context.trigger == .freedSlot, let slot = context.freedSlotWindow {
            triggerBlocks += PlanningPromptContextBuilder.freedSlotReplanBlock(
                removedTitle: context.removedTaskTitle ?? "Task",
                slotStart: slot.start,
                slotEnd: slot.end
            ) + "\n"
        }

        let tasksForPrompt = context.trigger == .freedSlot
            ? slotCandidateTasks(from: context)
            : context.planningContext.tasks

        return """
        \(PlanningPromptContextBuilder.temporalBlock(now: now, profile: profile))
        \(PlanningPromptContextBuilder.schedulingRulesBlock())
        \(PlanningPromptContextBuilder.dailyRoutineBlock())
        \(triggerBlocks)
        WEATHER: \(context.weatherSummary ?? "unknown")
        LOCATION: \(context.locationLabel ?? "unknown")
        GOALS: \(context.userGoals ?? "none")

        \(PlanningPromptContextBuilder.combinedLifeContextBlock(profile: profile))
        \(supplemental.isEmpty ? "" : "\(supplemental)\n")
        \(PlanningPromptContextBuilder.healthBlock(pc.healthSummary))
        \(PlanningPromptContextBuilder.executiveCapacityBlock(
            label: pc.executiveCapacityLabel,
            reasons: pc.executiveCapacityReasons,
            availableMinutes: pc.availableMinutes,
            completedTodayCount: pc.completedTodayCount,
            nextMeetingTitle: pc.nextMeetingTitle,
            nextMeetingMinutes: pc.nextMeetingMinutes,
            planSummary: pc.planSummary
        ))

        COMPLETED TODAY:
        \(completed.isEmpty ? "- none" : completed)

        \(PlanningPromptContextBuilder.tasksBlock(tasksForPrompt, style: .replanRemaining))
        \(PlanningPromptContextBuilder.timelineBlock(pc.timelineItems))
        \(PlanningPromptContextBuilder.medicationsBlock(pc.medications))

        Return JSON matching this schema (use actual ids/titles — never copy placeholders literally):
        \(PlanningPromptContextBuilder.dayReplanResponseSchema)
        """
    }

    private struct RawReplan: Codable {
        var summary: String
        var scheduleChanges: [RawChange]?
        var mutations: [PlanMutation]?
        var timelineDeltas: [PlanningTimelineDelta]?
        var planVariants: [RawVariant]?
        var recommendedVariantID: String?
    }

    private struct RawVariant: Codable {
        var id: String?
        var label: String
        var summary: String?
        var tradeoffs: [String]?
        var scheduleChanges: [RawChange]?
        var timelineDeltas: [PlanningTimelineDelta]?
        var recommended: Bool?
    }

    private struct RawChange: Codable {
        var taskID: String
        var startHour: Int?
        var startMinute: Int?
        var deferToTomorrow: Bool?
        var reason: String?
    }

    private func decode(raw: String, context: DayReplanContext) throws -> DayReplanResult {
        let clean = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let slice: String
        if let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}") {
            slice = String(clean[start...end])
        } else {
            slice = clean
        }

        if let data = slice.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(RawReplan.self, from: data) {
            let changes = (decoded.scheduleChanges ?? []).map {
                DayReplanScheduleChange(
                    taskID: $0.taskID,
                    startHour: $0.startHour,
                    startMinute: $0.startMinute,
                    deferToTomorrow: $0.deferToTomorrow ?? false,
                    reason: $0.reason ?? ""
                )
            }
            let variants = (decoded.planVariants ?? []).map { raw -> PlanVariant in
                PlanVariant(
                    id: raw.id ?? UUID().uuidString,
                    label: raw.label,
                    summary: raw.summary ?? raw.label,
                    tradeoffs: raw.tradeoffs ?? [],
                    scheduleChanges: (raw.scheduleChanges ?? []).map {
                        DayReplanScheduleChange(
                            taskID: $0.taskID,
                            startHour: $0.startHour,
                            startMinute: $0.startMinute,
                            deferToTomorrow: $0.deferToTomorrow ?? false,
                            reason: $0.reason ?? ""
                        )
                    },
                    timelineDeltas: raw.timelineDeltas ?? [],
                    recommended: raw.recommended ?? false
                )
            }
            var result = DayReplanResult(
                summary: decoded.summary,
                scheduleChanges: changes,
                mutations: decoded.mutations ?? [],
                timelineDeltas: decoded.timelineDeltas ?? [],
                planVariants: variants.isEmpty ? nil : variants,
                recommendedVariantID: decoded.recommendedVariantID
            )
            if result.scheduleChanges.isEmpty, let variants = result.planVariants, !variants.isEmpty {
                let pick = variants.first(where: \.recommended) ?? variants[0]
                result.summary = pick.summary.isEmpty ? result.summary : pick.summary
                result.scheduleChanges = pick.scheduleChanges
                result.timelineDeltas = pick.timelineDeltas
            }
            return result
        }

        return localFallback(context: context)
    }

    private func localFallback(context: DayReplanContext) -> DayReplanResult {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.startOfDay(for: now)
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: context.planningContext.lifeProfile)
        var changes: [DayReplanScheduleChange] = []

        if context.trigger == .postWake {
            for task in context.missedTasks where !task.isFixedTimeEvent && !task.isLifeCommitmentTask {
                changes.append(DayReplanScheduleChange(
                    taskID: task.id,
                    deferToTomorrow: true,
                    reason: "Missed morning window — moved to tomorrow"
                ))
            }
        }

        if context.trigger == .freedSlot, let slot = context.freedSlotWindow {
            return localFreedSlotFallback(context: context, slot: slot, calendar: calendar, now: now)
        }

        let flexible = context.planningContext.tasks.filter { task in
            guard task.status.isActive, !task.isFixedTimeEvent else { return false }
            return !changes.contains(where: { $0.taskID == task.id && $0.deferToTomorrow })
        }

        var slot = PlanningSchedulePolicy.nextAvailableSlot(workHours: workHours)
            ?? (workHours.startHour, 0)
        var slotDate = calendar.date(
            bySettingHour: slot.hour,
            minute: slot.minute,
            second: 0,
            of: day
        ) ?? now

        func advanceSlot() {
            slot = (min(slot.hour + 1, workHours.endHour), slot.minute)
            slotDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day) ?? slotDate.addingTimeInterval(3600)
        }

        func isInsideAwayWindow(_ date: Date) -> Bool {
            guard let away = context.awayWindow else { return false }
            return date >= away.start && date < away.end
        }

        for task in flexible.prefix(6) {
            while slotDate < now || isInsideAwayWindow(slotDate) {
                advanceSlot()
            }
            if context.trigger == .goingOut,
               let away = context.awayWindow,
               slotDate >= away.start {
                changes.append(DayReplanScheduleChange(
                    taskID: task.id,
                    deferToTomorrow: true,
                    reason: "No room before going out — deferred"
                ))
                continue
            }
            changes.append(DayReplanScheduleChange(
                taskID: task.id,
                startHour: slot.hour,
                startMinute: slot.minute,
                reason: context.trigger == .goingOut
                    ? "Fits before you head out"
                    : "Better fit for remaining energy"
            ))
            advanceSlot()
        }

        let hour = calendar.component(.hour, from: now)
        let summary: String
        switch context.trigger {
        case .postWake:
            let deferred = changes.filter(\.deferToTomorrow).count
            summary = deferred > 0
                ? "You're up — I deferred \(deferred) missed item\(deferred == 1 ? "" : "s") and reshaped what's still realistic today."
                : "You're up — I reshaped the rest of your morning around what still fits."
        case .goingOut:
            summary = "I compressed work around your outing and deferred what won't fit."
        case .freedSlot:
            summary = changes.isEmpty
                ? "That slot is open — nothing else fit cleanly without crowding the rest of your day."
                : "I found something that fits the time you just freed."
        case .calendarChange:
            summary = changes.isEmpty
                ? "Your calendar shifted — the rest of your day still fits as-is."
                : "I adjusted your plan around the new meeting."
        case .badDay, .recoveryDay:
            summary = "Recovery plan — I deferred non-essentials so today feels doable."
        case .travelDisruption:
            summary = "Travel changed — I reshuffled around your trip."
        case .generic:
            let periodLabel: String
            let pacingHint: String
            if hour >= 17 {
                periodLabel = "evening"
                pacingHint = "lighter items first while you still have energy"
            } else if hour >= 12 {
                periodLabel = "rest of your day"
                pacingHint = "what's left with your current energy"
            } else {
                periodLabel = "rest of your morning"
                pacingHint = "lighter work first, heavier items when focus is strongest"
            }
            summary = "I've reorganized your \(periodLabel) — \(pacingHint)."
        }

        return DayReplanResult(
            summary: summary,
            scheduleChanges: changes,
            timelineDeltas: flexible.prefix(2).map { task in
                PlanningTimelineDelta(
                    timeLabel: "—",
                    title: HumanLanguage.outcomeHeadline(task: task),
                    change: .moved
                )
            },
            planVariants: buildOfflineVariantsIfNeeded(context: context, baseChanges: changes, summary: summary)
        )
    }

    private func buildOfflineVariantsIfNeeded(
        context: DayReplanContext,
        baseChanges: [DayReplanScheduleChange],
        summary: String
    ) -> [PlanVariant]? {
        guard context.trigger == .calendarChange || context.trigger == .generic || context.trigger == .postWake else {
            return nil
        }
        let deferCandidates = context.planningContext.tasks.filter { task in
            task.status.isActive && !task.isFixedTimeEvent && baseChanges.contains(where: { $0.taskID == task.id && $0.deferToTomorrow })
        }
        let variants = PlanVariantBuilder.buildOfflineVariants(
            tasks: context.planningContext.tasks,
            deferCandidates: deferCandidates.isEmpty
                ? Array(context.planningContext.tasks.filter { $0.status.isActive && !$0.isFixedTimeEvent }.prefix(3))
                : deferCandidates,
            context: context
        )
        return variants.count >= 2 ? variants : nil
    }

    private func slotCandidateTasks(from context: DayReplanContext) -> [LifeTask] {
        guard let slot = context.freedSlotWindow else { return context.planningContext.tasks }
        let slotMinutes = FreedSlotWindow.slotMinutes(slot)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: slot.start)

        return context.planningContext.tasks.filter { task in
            guard task.status.isActive, task.isSchedulerMovable else { return false }
            let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            guard duration <= slotMinutes else { return false }

            if TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: day, calendar: calendar) {
                return true
            }
            if TaskScheduleInterval.window(for: task, on: day, calendar: calendar) != nil {
                return false
            }
            if let scheduledDate = task.scheduledDate {
                return calendar.isDate(scheduledDate, inSameDayAs: day)
            }
            return true
        }
    }

    private func localFreedSlotFallback(
        context: DayReplanContext,
        slot: DayReplanAwayWindow,
        calendar: Calendar,
        now: Date
    ) -> DayReplanResult {
        let slotMinutes = FreedSlotWindow.slotMinutes(slot)
        let candidates = slotCandidateTasks(from: context).sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.estimatedMinutes < rhs.estimatedMinutes
        }

        var changes: [DayReplanScheduleChange] = []
        var remaining = slotMinutes
        let slotDay = calendar.startOfDay(for: slot.start)
        let effectiveNow: Date = {
            if calendar.isDate(slotDay, inSameDayAs: now) {
                return max(slot.start, now)
            }
            return slot.start
        }()
        guard effectiveNow < slot.end else {
            return DayReplanResult(
                summary: "That slot is open — nothing else fit cleanly without crowding the rest of your day.",
                scheduleChanges: []
            )
        }
        var slotStart = effectiveNow
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        for task in candidates {
            let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            guard duration <= remaining else { continue }

            let end = slotStart.addingTimeInterval(TimeInterval(duration * 60))
            guard end <= slot.end else { continue }

            changes.append(DayReplanScheduleChange(
                taskID: task.id,
                startHour: calendar.component(.hour, from: slotStart),
                startMinute: calendar.component(.minute, from: slotStart),
                reason: "Fits the time you freed"
            ))
            remaining -= duration
            slotStart = end
            if remaining < TaskDurationPolicy.minimumMinutes { break }
        }

        let summary = changes.isEmpty
            ? "That slot is open — nothing else fit cleanly without crowding the rest of your day."
            : "I found something that fits the time you just freed."

        return DayReplanResult(
            summary: summary,
            scheduleChanges: changes,
            timelineDeltas: changes.prefix(2).map { change in
                let task = context.planningContext.tasks.first { $0.id == change.taskID }
                let label: String
                if let hour = change.startHour, let minute = change.startMinute,
                   let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: slotDay) {
                    label = formatter.string(from: time)
                } else {
                    label = "—"
                }
                return PlanningTimelineDelta(
                    timeLabel: label,
                    title: task.map { HumanLanguage.outcomeHeadline(task: $0) } ?? "Task",
                    change: .moved
                )
            }
        )
    }
}
