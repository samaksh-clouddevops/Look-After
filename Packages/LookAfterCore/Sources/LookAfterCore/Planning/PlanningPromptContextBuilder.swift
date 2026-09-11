import Foundation

/// Shared prompt sections for Executive Planning, Day Replan, and Daily Planner.
public enum PlanningPromptContextBuilder {

    public enum TaskListingStyle: Sendable {
        case planning
        case replanRemaining
        case schedulingFixed
        case schedulingFlexible
    }

    // MARK: - Schema placeholders (avoid few-shot leakage)

    public static let executivePlanningResponseSchema = """
    {
      "reply": "<warm plain-English message to user>",
      "thinkingSteps": ["<short reasoning label>"],
      "multiDayDraft": {
        "title": "<goal title>",
        "dayCount": <N>,
        "lifeArea": "Work|Health & Recovery|Music & Creativity|Learning & Knowledge|Personal",
        "deadlineISO": "<optional ISO8601>",
        "reasoning": "<why this N and breakdown>",
        "slices": [
          {"dayIndex": 0, "title": "<slice title>", "estimatedMinutes": 45, "windowLabel": "Office|Creative Deep Work|Gym"}
        ]
      },
      "multiDayPlanning": {
        "question": "Does this plan work for you?",
        "options": ["Schedule it", "Use fewer days", "Use more days", "Change the slices", "Cancel"]
      },
      "mutations": [
        {"kind":"reuseTask","title":"<exact title from TASKS>","taskID":"<id from TASKS>","reason":"<why>"},
        {"kind":"createTask","title":"<user-requested title>","estimatedMinutes":<minutes>,"priority":"Critical|High|Medium|Low","startHour":<0-23>,"startMinute":<0-59>},
        {"kind":"createMultiDayTask","title":"<goal>","dayCount":<N>,"deadlineISO":"<optional>","slices":[{"dayIndex":0,"title":"<slice>","estimatedMinutes":45}]},
        {"kind":"markMedicationTaken","medicationID":"<id from MEDICATIONS>"},
        {"kind":"addShoppingItem","shoppingItemName":"<item>"},
        {"kind":"deferTask","taskID":"<id from TASKS>"},
        {"kind":"rescheduleTask","taskID":"<id from TASKS>","startHour":<0-23>,"startMinute":<0-59>}
      ],
      "negotiation": {"question":"<overload question>","options":["<option1>","<option2>"],"optionVariantIDs":["<variant-id-1>","<variant-id-2>"]},
      "planVariants": [
        {"id":"protect-focus","label":"Protect deep work","summary":"<trade-off summary>","tradeoffs":["<pro>","<con>"],"recommended":true,"scheduleChanges":[{"taskID":"<id>","deferToTomorrow":true,"reason":"<why>"}],"timelineDeltas":[{"timeLabel":"—","title":"<task>","change":"removed"}]}
      ],
      "timelineDeltas": [
        {"timeLabel":"<h:mm AM/PM>","title":"<task title>","change":"added|moved|removed|reused|conflict","isConflict":false}
      ]
    }
    """

    public static let dayReplanResponseSchema = """
    {
      "summary": "<human paragraph — no block jargon>",
      "recommendedVariantID": "<id of best variant>",
      "planVariants": [
        {"id":"protect-focus","label":"Protect deep work","summary":"<human summary>","tradeoffs":["<pro>","<con>"],"recommended":true,"scheduleChanges":[{"taskID":"<id from REMAINING>","deferToTomorrow":true,"reason":"<why>"}],"timelineDeltas":[{"timeLabel":"<h:mm AM/PM>","title":"<task>","change":"moved|removed"}]}
      ],
      "scheduleChanges": [
        {"taskID":"<id from REMAINING>","startHour":<0-23>,"startMinute":<0-59>,"deferToTomorrow":false,"reason":"<why>"},
        {"taskID":"<id from REMAINING>","deferToTomorrow":true,"reason":"<why defer>"}
      ],
      "mutations": [],
      "timelineDeltas": [
        {"timeLabel":"<h:mm AM/PM>","title":"<task title>","change":"moved|added|removed","isConflict":false}
      ]
    }
    """

    public static let dailySchedulerResponseSchema = """
    [
      {"id":"<FLEXIBLE task id>","startHour":<0-23>,"startMinute":<0-59>,"reason":"<short why>"}
    ]
    """

    // MARK: - Blocks

    public static func temporalBlock(
        now: Date = Date(),
        profile: UserLifeProfile,
        planningDay: Date? = nil
    ) -> String {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let targetDay = planningDay.map { calendar.startOfDay(for: $0) } ?? todayStart
        let isToday = calendar.isDate(targetDay, inSameDayAs: todayStart)
        let isTomorrow: Bool = {
            guard !isToday,
                  let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return false }
            return calendar.isDate(targetDay, inSameDayAs: tomorrowStart)
        }()

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d, yyyy"
        let dayLabel = dayFormatter.string(from: targetDay)

        let windows = SchedulingWindows.from(profile: profile)
        var lines = [
            "CURRENT TIME: \(now.formatted(date: .abbreviated, time: .shortened))",
            "PLANNING FOR: \(isToday ? "Today" : isTomorrow ? "Tomorrow" : "Future day") — \(dayLabel)",
            "DAY TYPE: \(calendar.isDateInWeekend(targetDay) ? "weekend" : "weekday")",
            "OFFICE HOURS: \(formatHour(windows.officeHours.startHour)) – \(formatHour(windows.officeHours.endHour))",
            "PEAK ENERGY: \(formatHour(profile.peakStartHour)) – \(formatHour(profile.peakEndHour))"
        ]

        if let model = LifeModelStore.load(), model.hasContent {
            let blocksForDay = model.timeBlocks.filter { $0.days.includes(targetDay, calendar: calendar) }
            if !blocksForDay.isEmpty {
                lines.append("BLOCKS ON THIS DAY (from life model):")
                for block in blocksForDay {
                    let protection = block.protection == .neverSchedule ? "NEVER SCHEDULE OVER" : block.protection.rawValue
                    lines.append("- \(block.label): \(block.timeRangeLabel()) [\(protection)]")
                }
            }

            let commitmentsForDay = model.commitments.filter { $0.frequency.applies(on: targetDay, calendar: calendar) }
            if !commitmentsForDay.isEmpty {
                lines.append("LIFE COMMITMENTS ON THIS DAY:")
                for commitment in commitmentsForDay.sorted(by: { $0.priority < $1.priority }) {
                    let block = commitment.preferredBlockLabel ?? "flexible"
                    lines.append("- \(commitment.title): \(commitment.defaultMinutes)m in \(block)")
                }
            }
        } else if !windows.creativeWindows.isEmpty {
            let creative = windows.creativeWindows.map {
                "\(formatHour($0.startHour)) – \(formatHour($0.endHour))"
            }.joined(separator: ", ")
            lines.append("CREATIVE WINDOWS: \(creative)")
        }

        for block in windows.protectedBlocks where block.protection == .neverSchedule {
            lines.append("PROTECTED (never schedule over): \(block.label) \(block.timeRangeLabel())")
        }

        if isToday {
            lines.append("Schedule flexible work in OFFICE HOURS and/or CREATIVE WINDOWS — never before CURRENT TIME.")
        } else {
            lines.append("Schedule flexible work across the full PLANNING FOR day — do not use CURRENT TIME as a lower bound.")
        }
        lines.append("Never schedule over PROTECTED blocks. Never use midnight unless user explicitly asked.")
        lines.append("Respect each task's semantic type, preferred windows, and fixed vs flexible scheduling mode.")

        return lines.joined(separator: "\n")
    }

    public static func lifeModelBlock(_ model: LifeModel?) -> String {
        guard let model, model.hasContent else {
            return "LIFE MODEL: not compiled yet — use USER LIFE PROFILE fallback."
        }

        var lines: [String] = ["LIFE MODEL (compiled — this is who the user is):"]

        if !model.identity.name.isEmpty {
            lines.append("NAME: \(model.identity.name)")
        }
        if !model.identity.roleFraming.isEmpty {
            lines.append("IDENTITY: \(model.identity.roleFraming)")
        }
        if !model.identity.mission.isEmpty {
            lines.append("MISSION: \(model.identity.mission)")
        }
        if !model.priorities.isEmpty {
            lines.append("PRIORITIES (in order):")
            for (index, priority) in model.priorities.enumerated() {
                lines.append("  \(index + 1). \(priority)")
            }
        }

        if !model.timeBlocks.isEmpty {
            lines.append("PROTECTED TIME BLOCKS:")
            for block in model.timeBlocks {
                let protection = block.protection == .neverSchedule ? "NEVER SCHEDULE OVER" : block.protection.rawValue
                lines.append("- \(block.label): \(block.timeRangeLabel()) [\(protection)]")
                if let order = block.priorityOrder, !order.isEmpty {
                    lines.append("  Priority inside block: \(order.joined(separator: " → "))")
                }
            }
        }

        if !model.commitments.isEmpty {
            lines.append("LIFE COMMITMENTS (brain maintains these — do not ask user to create manually):")
            for commitment in model.commitments.sorted(by: { $0.priority < $1.priority }) {
                let block = commitment.preferredBlockLabel ?? "flexible"
                lines.append("- \(commitment.title): \(commitment.defaultMinutes)m, block=\(block), priority=\(commitment.priority)\(commitment.isNonNegotiable ? ", NON-NEGOTIABLE" : "")")
            }
        }

        if !model.adhdRules.isEmpty {
            lines.append("ADHD RULES:\n\(model.adhdRules)")
        }
        if !model.coachingRules.isEmpty {
            lines.append("ACCOUNTABILITY:\n\(model.coachingRules)")
        }
        if !model.decisionFramework.isEmpty {
            lines.append("DECISION FRAMEWORK:")
            for (index, step) in model.decisionFramework.enumerated() {
                lines.append("  \(index + 1). \(step)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Prefers compiled life model; falls back to legacy profile text.
    public static func combinedLifeContextBlock(profile: UserLifeProfile) -> String {
        if let model = LifeModelStore.load(), model.hasContent {
            return lifeModelBlock(model)
        }
        return lifeProfileBlock(profile)
    }

    public static func lifeProfileBlock(_ profile: UserLifeProfile) -> String {
        """
        USER LIFE PROFILE:
        \(profile.promptBlock.isEmpty ? "- not configured yet" : profile.promptBlock)
        """
    }

    public static func executiveCapacityBlock(
        label: String,
        reasons: [String],
        availableMinutes: Int,
        completedTodayCount: Int = 0,
        nextMeetingTitle: String? = nil,
        nextMeetingMinutes: Int? = nil,
        planSummary: String = ""
    ) -> String {
        let meetingLine: String
        if let title = nextMeetingTitle, let mins = nextMeetingMinutes {
            meetingLine = "Next meeting: \(title) in \(mins) minutes"
        } else {
            meetingLine = "No imminent meetings"
        }
        var block = """
        LIFE STATE:
        - Available minutes today: \(availableMinutes)
        - Executive Capacity: \(label)
        - Because: \(reasons.isEmpty ? "baseline signals" : reasons.joined(separator: "; "))
        - Completed today: \(completedTodayCount)
        - \(meetingLine)
        """
        if !planSummary.isEmpty {
            block += "\n- Plan summary: \(planSummary)"
        }
        return block
    }

    public static func healthBlock(_ summary: HealthSummary?, targetSleepHours: Double = 7.5) -> String {
        guard let summary else {
            return """
            APPLE HEALTH (imported today):
            - not connected or no data imported yet
            - treat energy as unknown; avoid assuming good sleep or high recovery
            """
        }

        var lines: [String] = []

        if let manual = ManualSleepLogStore.entry(for: Date()) {
            lines.append("- Self-reported sleep last night: \(manual.rating.label) (\(manual.rating.emoji)) — use for pacing and defer decisions")
        } else if let sleepMin = summary.totalSleepMinutes, sleepMin > 0 {
            let hours = sleepMin / 60.0
            let quality: String
            if hours >= targetSleepHours + 0.5 {
                quality = "well rested"
            } else if hours >= targetSleepHours - 1 {
                quality = "adequate"
            } else {
                quality = "short — protect focus and defer heavy work"
            }
            lines.append("- Sleep last night: \(String(format: "%.1f", hours))h (\(quality))")
            if let deep = summary.deepSleepMinutes, deep > 0 {
                lines.append("- Deep sleep: \(Int(deep)) min")
            }
            if let rem = summary.remSleepMinutes, rem > 0 {
                lines.append("- REM sleep: \(Int(rem)) min")
            }
        } else {
            lines.append("- Sleep: not recorded last night")
        }

        if let steps = summary.stepCount, steps > 0 {
            lines.append("- Steps today: \(steps)")
        }
        if let hrv = summary.hrvAverage {
            let trend = summary.hrvTrend ?? "stable"
            lines.append("- HRV: \(Int(hrv)) ms (\(trend))")
        }
        if let rhr = summary.restingHeartRate {
            lines.append("- Resting heart rate: \(Int(rhr)) bpm")
        }
        if let exercise = summary.exerciseMinutes, exercise > 0 {
            lines.append("- Exercise: \(exercise) min")
        }
        if let workouts = summary.workoutCount, workouts > 0 {
            let types = summary.workoutTypes?.prefix(2).joined(separator: ", ") ?? "logged"
            lines.append("- Workouts: \(workouts) (\(types))")
        }

        if lines.isEmpty {
            lines.append("- HealthKit connected but no metrics imported for today yet")
        }

        return """
        APPLE HEALTH (imported today — use for pacing and defer decisions):
        \(lines.joined(separator: "\n"))
        """
    }

    public static func cycleBlock(snapshot: CycleSnapshot? = nil, logs: [CycleDayLog] = []) -> String {
        guard CycleFeatureGate.isActive else { return "" }
        guard let snapshot, snapshot.isEnabled else { return "" }
        var lines: [String] = []
        if let day = snapshot.cycleDay {
            lines.append("- Cycle day \(day), phase: \(snapshot.phase.displayLabel)")
        } else {
            lines.append("- Phase: \(snapshot.phase.displayLabel) (still learning cycle)")
        }
        if let countdown = snapshot.periodCountdownLabel {
            lines.append("- \(countdown)")
        }
        let recentSymptoms = logs.prefix(7).flatMap(\.symptoms)
        if !recentSymptoms.isEmpty {
            lines.append("- Recent symptoms: \(Array(Set(recentSymptoms)).prefix(5).joined(separator: ", "))")
        }
        lines.append("- Adjust plan for phase — protect energy during menstrual/luteal when user logs low energy.")
        return """
        CYCLE CONTEXT (opt-in user data — reference actual logs, not stereotypes):
        \(lines.joined(separator: "\n"))
        """
    }

    public static func medicationsBlock(_ medications: [Medication], now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let lines = medications.map { med in
            let taken = med.isTaken ? "taken" : "due"
            return "- id:\(med.id) | \(med.name) | \(formatter.string(from: med.scheduledTime)) | \(taken)"
        }
        return """
        MEDICATIONS (never invent times — use these ids only):
        \(lines.isEmpty ? "- none configured" : lines.joined(separator: "\n"))
        """
    }

    public static func timelineBlock(_ items: [LifeTimelineEvent], limit: Int = 20) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let lines = items.prefix(limit).map { item in
            "- \(formatter.string(from: item.date)) | \(item.title) | \(item.kind.rawValue)"
        }
        return """
        TIMELINE:
        \(lines.isEmpty ? "- empty" : lines.joined(separator: "\n"))
        """
    }

    public static func tasksBlock(_ tasks: [LifeTask], style: TaskListingStyle, limit: Int = 25) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let filtered: [LifeTask]
        switch style {
        case .planning:
            filtered = Array(tasks.prefix(limit))
        case .replanRemaining:
            filtered = tasks.filter(\.status.isActive).prefix(limit).map { $0 }
        case .schedulingFixed:
            filtered = tasks.filter(\.isFixedTimeEvent).prefix(limit).map { $0 }
        case .schedulingFlexible:
            filtered = tasks.filter { !$0.isFixedTimeEvent }.prefix(limit).map { $0 }
        }

        let lines = filtered.map { task in
            formatTaskLine(task, style: style, formatter: formatter)
        }
        let header: String
        switch style {
        case .planning: header = "TASKS"
        case .replanRemaining: header = "REMAINING (replan from now)"
        case .schedulingFixed: header = "FIXED events (do not change times)"
        case .schedulingFlexible: header = "FLEXIBLE tasks (assign start times)"
        }
        return """
        \(header):
        \(lines.isEmpty ? "- none" : lines.joined(separator: "\n"))
        """
    }

    public static func analyticsBlock(_ summary: CachedAIContextSummary?) -> String {
        guard let block = summary?.promptBlock, !block.isEmpty else { return "" }
        return block
    }

    public static func calibrationBlock() -> String {
        let block = UserCalibrationStore.promptBlock()
        return block.isEmpty ? "" : block
    }

    public static func supplementalContextBlock(
        analytics: CachedAIContextSummary? = nil,
        includeCalibration: Bool = true
    ) -> String {
        var parts: [String] = []
        let analyticsText = analyticsBlock(analytics)
        if !analyticsText.isEmpty { parts.append(analyticsText) }
        if includeCalibration {
            let calibration = calibrationBlock()
            if !calibration.isEmpty { parts.append(calibration) }
        }
        if CyclePreferencesStore.isActive {
            let cycle = cycleBlock(
                snapshot: CycleEngine.snapshot(CycleEngine.Input()),
                logs: CycleLogStore.load()
            )
            if !cycle.isEmpty { parts.append(cycle) }
        }
        return parts.joined(separator: "\n\n")
    }

    public static func duplicateReuseRulesBlock() -> String {
        """
        DUPLICATE / REUSE RULES:
        - Reuse existing tasks ONLY when the user clearly refers to the same item.
        - Use kind "reuseTask" with the exact task id — never duplicate on partial word overlap.
        - When overloaded, prefer deferTask/removeFromToday over silently adding work.
        RESCHEDULE RULES:
        - When the user asks to move, shift, push, or reschedule an EXISTING task to a new time, use kind "rescheduleTask" with taskID from TASKS and startHour/startMinute.
        - NEVER use createTask when the user refers to an existing task by name or id and wants a new time.
        - If no exact time is given, pick the nearest open slot after fixed blocks and include startHour/startMinute.
        """
    }

    public static func proactiveSuggestionsBlock(_ suggestions: [ScheduleProactiveSuggestion]) -> String {
        guard !suggestions.isEmpty else { return "" }
        let lines = suggestions.prefix(3).map { "- [\($0.severity.rawValue)] \($0.message)" }
        return """
        PROACTIVE SCHEDULE NOTES (mention gently if relevant; use negotiation options when user agrees):
        \(lines.joined(separator: "\n"))
        """
    }

    public static func schedulingRulesBlock(
        bufferMinutes: Int = 5,
        planningDay: Date? = nil,
        now: Date = Date()
    ) -> String {
        let calendar = Calendar.current
        let isFutureDay = planningDay.map {
            !calendar.isDate(calendar.startOfDay(for: $0), inSameDayAs: calendar.startOfDay(for: now))
        } ?? false

        let timeRule = isFutureDay
            ? "- PLANNING FOR a future day — schedule across the full target day; do NOT use CURRENT TIME as a lower bound."
            : "- Never schedule before CURRENT TIME."

        return """
        SCHEDULING RULES:
        - Analyze the user's request against CURRENT TIME, today's date, TASKS, and TIMELINE before creating work.
        - Never move or overlap FIXED tasks (fixed:true) or life-commitment tasks — schedule flexible work around them.
        - Only ONE music/creative life-commitment activity per day — never assign times to duplicate creative commitments; omit them from output.
        - Sort new work by priority (Critical/High before Medium/Low) when suggesting times.
        - Every createTask must include estimatedMinutes and, when possible, startHour/startMinute after fixed blocks.
        \(timeRule)
        - Respect work hours, creative windows, and protected blocks in LIFE MODEL / USER LIFE PROFILE.
        - Include \(bufferMinutes)-minute buffers between flexible tasks — no overlaps; never assign the same start time to two tasks.
        - Put demanding work in peak energy windows when possible.
        - If user states a duration (e.g. "1 min"), use that exact estimatedMinutes — do not inflate.
        - Never invent medication times — use MEDICATIONS list only.
        - Created tasks appear on the user's timeline with start time and duration — omit times only if negotiating overload.
        - Slot flexible routines (Morning review) into open windows when capacity allows — skip if overloaded.
        - Protect daily meal blocks (Breakfast, Lunch, Snacks, Dinner) and hygiene (Brush teeth) as fixed anchors.
        """
    }

    public static func dailyRoutineBlock() -> String {
        if let model = LifeModelStore.load(), model.hasContent {
            var lines = ["DAILY ROUTINES (anchor the day — schedule flexible work around these):"]
            let mealCommitments = model.commitments.filter {
                $0.lifeArea == .health && ($0.title.lowercased().contains("dinner") || $0.title == "Dinner")
            }
            for commitment in mealCommitments {
                if let block = commitment.preferredBlockLabel.flatMap({ model.block(matching: $0) }) {
                    lines.append("- \(commitment.title): \(formatHour(block.startHour)) – \(formatHour(block.endHour))")
                }
            }
            let dinnerBlock = model.timeBlocks.first { $0.label.lowercased().contains("dinner") }
            if dinnerBlock != nil, !mealCommitments.contains(where: { $0.title == "Dinner" }) {
                lines.append("- Dinner: \(formatHour(dinnerBlock!.startHour)) – \(formatHour(dinnerBlock!.endHour))")
            }
            if lines.count == 1 {
                lines.append("- Meals: Breakfast ~8:00 AM, Lunch ~12:30 PM, Snacks ~4:00 PM, Dinner ~7:00 PM")
            }
            lines.append("- Hygiene: Brush teeth after waking ~7:30 AM and before bed ~9:30 PM")
            lines.append("- Medication: use MEDICATIONS list — never invent times")
            lines.append("- Morning review: 10 min flexible block after breakfast when capacity allows")
            lines.append("- End-of-day reflection lives on the Timeline screen (not a schedulable task)")
            return lines.joined(separator: "\n")
        }

        return """
        DAILY ROUTINES (anchor the day — schedule flexible work around these):
        - Meals: Breakfast ~8:00 AM, Lunch ~12:30 PM, Snacks ~4:00 PM, Dinner ~7:00 PM
        - Hygiene: Brush teeth after waking ~7:30 AM and before bed ~9:30 PM
        - Medication: use MEDICATIONS list — never invent times
        - Morning review: 10 min flexible block after breakfast when capacity allows
        - End-of-day reflection lives on the Timeline screen (not a schedulable task)
        - Sleep fence: nothing new after ideal bedtime — wind-down marks end of actionable day
        - Missed hygiene/meals from yesterday do NOT duplicate today's occurrence; add ONE catch-up task with a clear title (e.g. "Brush teeth (catch-up)") only when context warrants it
        """
    }

    public static func sleepBoundaryBlock(now: Date = Date(), profile: UserLifeProfile = UserLifeProfileStore.load()) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let bedtime = DayBoundaryPlanner.actionableDayEnd(on: day, now: now, calendar: calendar)
        let label = ScheduleTimeFormatting.timeLabel(bedtime, calendar: calendar)
        return """
        SLEEP BOUNDARY:
        - Ideal wind-down begins by \(label)
        - Do not schedule flexible work after this time
        - Keep meals in their windows (Breakfast before 11 AM, Dinner before 9 PM)
        """
    }

    public static func missedTasksBlock(_ tasks: [LifeTask]) -> String {
        guard !tasks.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let lines = tasks.map { task -> String in
            let time = task.scheduledTime.map { formatter.string(from: $0) } ?? "unscheduled"
            return "- MISSED id:\(task.id) | \(task.title) | was:\(time) | \(task.estimatedMinutes)m | fixed:\(task.isFixedTimeEvent)"
        }
        return """
        MISSED TASKS (window already passed — decide defer vs salvage for each):
        \(lines.joined(separator: "\n"))
        For each missed task: set deferToTomorrow:true OR reschedule if still high-value and fits.
        Use removeFromToday mutation only for low-value ephemeral items.
        """
    }

    public static func postWakeReplanBlock(wakeTime: Date, minutesLate: Int?) -> String {
        let wakeLabel = wakeTime.formatted(date: .omitted, time: .shortened)
        let lateLine = minutesLate.map { "User is \($0) minutes behind expected wake." } ?? "User woke later than planned."
        return """
        POST-WAKE CONTEXT:
        - User just woke up at \(wakeLabel)
        - \(lateLine)
        - Prioritize salvage over guilt — defer low-value missed items
        - Do not stack catch-up that exceeds remaining capacity
        """
    }

    public static func goingOutBlock(departure: Date, durationMinutes: Int, endTime: Date) -> String {
        """
        GOING OUT CONTEXT:
        - Departure: \(departure.formatted(date: .omitted, time: .shortened))
        - Duration: \(durationMinutes) minutes
        - Unavailable until: \(endTime.formatted(date: .omitted, time: .shortened))
        - AWAY WINDOW is hard busy — no movable tasks inside this range
        - Pack high-priority work before departure; defer overflow to after return or tomorrow
        """
    }

    public static func freedSlotReplanBlock(removedTitle: String, slotStart: Date, slotEnd: Date) -> String {
        let startLabel = slotStart.formatted(date: .omitted, time: .shortened)
        let endLabel = slotEnd.formatted(date: .omitted, time: .shortened)
        let minutes = max(Int(slotEnd.timeIntervalSince(slotStart) / 60), TaskDurationPolicy.minimumMinutes)
        return """
        FREED SLOT CONTEXT:
        - User removed "\(removedTitle)" from today's timeline
        - Open window: \(startLabel) – \(endLabel) (\(minutes) minutes)
        - Only schedule movable tasks whose full duration fits inside this window
        - Do not move anchored/fixed commitments or tasks already placed outside this slot
        """
    }

    // MARK: - Helpers

    private static func formatTaskLine(_ task: LifeTask, style: TaskListingStyle, formatter: DateFormatter) -> String {
        let time = task.scheduledTime.map { formatter.string(from: $0) } ?? "unscheduled"
        let day = task.scheduledDate?.formatted(date: .abbreviated, time: .omitted) ?? "unscheduled-day"
        let semantic = task.semanticProfile?.semanticType.rawValue ?? "generic"
        let subtype: String = {
            guard let value = task.semanticProfile?.subtype, !value.isEmpty else { return "" }
            return ", subtype:\(value)"
        }()
        let deadline = task.deadline.map { "due:\($0.shortDateString)" } ?? "no-deadline"
        let lifeCommitment = task.tags.contains(LifeModel.commitmentTaskTag) ? ", life-commitment" : ""

        switch style {
        case .planning:
            return "- id:\(task.id) | \(task.title) | day:\(day) | \(time) | \(task.estimatedMinutes)m | \(task.priority.label) | fixed:\(task.isFixedTimeEvent) | \(deadline) | semantic:\(semantic)\(subtype)\(lifeCommitment) | status:\(task.status.rawValue)"
        case .replanRemaining:
            return "- id:\(task.id) | \(task.title) | day:\(day) | \(time) | \(task.estimatedMinutes)m | fixed:\(task.isFixedTimeEvent) | semantic:\(semantic)\(subtype)"
        case .schedulingFixed:
            let start = task.scheduledTime?.formatted(date: .omitted, time: .shortened) ?? "unknown"
            let end = task.scheduledEndTime?.formatted(date: .omitted, time: .shortened) ?? "unknown"
            return "- FIXED id: \(task.id), title: \(task.title), day: \(day), window: \(start)–\(end), minutes: \(task.estimatedMinutes), semantic: \(semantic)\(subtype)"
        case .schedulingFlexible:
            let preferred = task.semanticProfile?.preferredTimeWindows.map(\.rawValue).joined(separator: ",") ?? "any"
            let forbidden = task.semanticProfile?.forbiddenTimeWindows.map(\.rawValue).joined(separator: ",") ?? "none"
            return "- FLEX id: \(task.id), title: \(task.title), day: \(day), minutes: \(task.estimatedMinutes), priority: \(task.priority.label), energy: \(task.requiredEnergy.rawValue), overdue: \(task.isOverdue), preferred: \(preferred), forbidden: \(forbidden), semantic: \(semantic)\(subtype)\(lifeCommitment)"
        }
    }

    public static func formatHour(_ hour: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: min(max(hour, 0), 23), minute: 0, second: 0, of: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
