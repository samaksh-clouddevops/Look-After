import Foundation
import LookAfterCore
import LookAfterAI

// MARK: - Context

public struct DayReplanContext: Sendable {
    public var planningContext: PlanningConversationContext
    public var completedTasks: [LifeTask]
    public var weatherSummary: String?
    public var sleepHours: Double?
    public var locationLabel: String?
    public var userGoals: String?

    public init(
        planningContext: PlanningConversationContext,
        completedTasks: [LifeTask],
        weatherSummary: String? = nil,
        sleepHours: Double? = nil,
        locationLabel: String? = nil,
        userGoals: String? = nil
    ) {
        self.planningContext = planningContext
        self.completedTasks = completedTasks
        self.weatherSummary = weatherSummary
        self.sleepHours = sleepHours
        self.locationLabel = locationLabel
        self.userGoals = userGoals
    }
}

public struct DayReplanScheduleChange: Sendable, Equatable {
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

    public init(
        summary: String,
        scheduleChanges: [DayReplanScheduleChange] = [],
        mutations: [PlanMutation] = [],
        timelineDeltas: [PlanningTimelineDelta] = []
    ) {
        self.summary = summary
        self.scheduleChanges = scheduleChanges
        self.mutations = mutations
        self.timelineDeltas = timelineDeltas
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
        let system = """
        You are the Executive Brain replanning the REST of today from the current moment.
        Never use internal labels (Deep Work Block, Focus Block, Planning Block, Session 1).
        Communicate in human actions. Simulate multiple schedules mentally, pick lowest executive cost.
        Defer work to tomorrow when meetings or energy make it unrealistic — explain why in summary.
        Never invent medication times. Return ONLY valid JSON — no markdown fences.
        \(PlanningPromptContextBuilder.duplicateReuseRulesBlock())
        """

        let raw: String
        do {
            raw = try await glm.sendMessage(prompt, systemPrompt: system, history: [])
        } catch {
            print("[DayReplan] AI unavailable: \(error.localizedDescription)")
            return localFallback(context: context)
        }
        return try decode(raw: raw, context: context)
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

        return """
        \(PlanningPromptContextBuilder.temporalBlock(now: now, profile: profile))
        \(PlanningPromptContextBuilder.schedulingRulesBlock())
        \(PlanningPromptContextBuilder.dailyRoutineBlock())
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

        \(PlanningPromptContextBuilder.tasksBlock(pc.tasks, style: .replanRemaining))
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
            return DayReplanResult(
                summary: decoded.summary,
                scheduleChanges: changes,
                mutations: decoded.mutations ?? [],
                timelineDeltas: decoded.timelineDeltas ?? []
            )
        }

        return localFallback(context: context)
    }

    private func localFallback(context: DayReplanContext) -> DayReplanResult {
        let flexible = context.planningContext.tasks.filter { $0.status.isActive && !$0.isFixedTimeEvent }
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: context.planningContext.lifeProfile)
        var changes: [DayReplanScheduleChange] = []
        var slot = PlanningSchedulePolicy.nextAvailableSlot(workHours: workHours)
            ?? (workHours.startHour, 0)

        for task in flexible.prefix(4) {
            changes.append(DayReplanScheduleChange(
                taskID: task.id,
                startHour: slot.hour,
                startMinute: slot.minute,
                reason: "Better fit for remaining energy"
            ))
            slot = (min(slot.hour + 1, workHours.endHour), slot.minute)
        }

        let hour = Calendar.current.component(.hour, from: Date())
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
        return DayReplanResult(
            summary: "I've reorganized your \(periodLabel) — \(pacingHint).",
            scheduleChanges: changes,
            timelineDeltas: flexible.prefix(2).map { task in
                PlanningTimelineDelta(
                    timeLabel: "—",
                    title: HumanLanguage.outcomeHeadline(task: task),
                    change: .moved
                )
            }
        )
    }
}
