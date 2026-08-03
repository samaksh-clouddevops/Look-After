import Foundation
import LifeOSCore

enum BrainPresentationBuilder {

    static func build(
        heroBriefing: HeroBriefing?,
        resumeSnapshot: ResumeSnapshot?,
        executiveCapacity: ExecutiveCapacityState,
        lifeSnapshot: LifeContextSnapshot?,
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?,
        healthSummary: HealthSummary?,
        activeTasks: [LifeTask],
        upcomingBills: [BillItem],
        medications: [Medication],
        timelineItems: [LifeTimelineEvent],
        readinessLabel: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BrainPresentation {
        let heroTask = resolveHeroTask(
            heroBriefing: heroBriefing,
            flowSurface: flowSurface,
            activeTasks: activeTasks,
            lifeSnapshot: lifeSnapshot,
            now: now,
            calendar: calendar
        )

        let hero = buildHero(
            task: heroTask,
            heroBriefing: heroBriefing,
            flowSurface: flowSurface,
            activeTasks: activeTasks,
            lifeSnapshot: lifeSnapshot,
            executiveCapacity: executiveCapacity,
            now: now,
            calendar: calendar
        )

        let backup = backupTasks(
            excludingHeroID: heroTask?.id,
            from: activeTasks,
            capacity: executiveCapacity
        )

        let resume = buildResume(resumeSnapshot, now: now, calendar: calendar)
        let capacity = buildCapacity(
            executiveCapacity: executiveCapacity,
            lifeSnapshot: lifeSnapshot,
            healthSummary: healthSummary,
            cognitiveSnapshot: cognitiveSnapshot
        )
        let headsUp = buildHeadsUp(
            medications: medications,
            bills: upcomingBills,
            timelineItems: timelineItems,
            now: now,
            calendar: calendar
        )

        let flowWindow = flowWindowLabel(flowSurface: flowSurface)
        let coachMoment = flowSurface?.coachMoment.flatMap { moment in
            moment.message.isEmpty ? nil : UserFacingCopy.sanitize(moment.message)
        }
        let confidence = confidenceLabel(from: heroBriefing)
        let greeting = resolvedGreeting(from: heroBriefing, now: now, calendar: calendar)
        let readiness = readinessLabel ?? resolvedReadiness(from: cognitiveSnapshot)

        return BrainPresentation(
            greeting: greeting,
            readinessLabel: readiness,
            hero: hero,
            backupTasks: backup,
            resume: resume,
            capacity: capacity,
            headsUp: headsUp,
            flowWindowLabel: flowWindow,
            coachMoment: coachMoment,
            confidenceLabel: confidence
        )
    }

    private static func resolvedGreeting(from hero: HeroBriefing?, now: Date, calendar: Calendar) -> String {
        if let hero, !hero.greeting.isEmpty {
            return UserFacingCopy.sanitize(hero.greeting)
        }
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    private static func resolvedReadiness(from snapshot: CognitiveSnapshot?) -> String {
        let score = Int((snapshot?.recoveryScore ?? 0.5) * 100)
        return UserFacingCopy.readinessLabel(score: score)
    }

    // MARK: - Hero

    private static func resolveHeroTask(
        heroBriefing: HeroBriefing?,
        flowSurface: FlowSurface?,
        activeTasks: [LifeTask],
        lifeSnapshot: LifeContextSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LifeTask? {
        let candidates: [LifeTask?] = [
            heroBriefing?.action.taskID.flatMap { id in activeTasks.first(where: { $0.id == id }) },
            flowSurface?.heroTask,
            lifeSnapshot?.currentMission,
            activeTasks.first
        ]

        for candidate in candidates {
            guard let task = candidate else { continue }
            if TaskHeroEligibility.isEligible(
                for: task,
                now: now,
                calendar: calendar,
                allTasks: activeTasks
            ) {
                return task
            }
        }
        return nil
    }

    private static func buildHero(
        task: LifeTask?,
        heroBriefing: HeroBriefing?,
        flowSurface: FlowSurface?,
        activeTasks: [LifeTask],
        lifeSnapshot: LifeContextSnapshot?,
        executiveCapacity: ExecutiveCapacityState,
        now: Date,
        calendar: Calendar
    ) -> BrainHeroPresentation? {
        if let heroBriefing, let task {
            return BrainHeroPresentation(
                task: task,
                title: headline(from: heroBriefing, task: task),
                supportingLine: supportingLine(from: heroBriefing, flowSurface: flowSurface, task: task),
                scheduledLabel: scheduledLabel(for: task, calendar: calendar),
                durationMinutes: durationMinutes(from: heroBriefing, task: task, flowSurface: flowSurface),
                whyReasons: Array(heroBriefing.whyNowReasons.prefix(4)),
                buttonLabel: UserFacingCopy.sanitize(heroBriefing.buttonLabel),
                isPastDue: isPastDue(task: task, now: now, calendar: calendar),
                kind: LifeTimelinePresenter.kindForTask(task)
            )
        }

        if let recommendation = ExecutiveRecommendationEngine.recommend(
            from: ExecutiveRecommendationEngine.Input(
                task: task,
                snapshot: lifeSnapshot ?? LifeContextSnapshot(currentEnergy: 0.6, availableTimeMinutes: 60),
                tasks: activeTasks,
                now: now,
                calendar: calendar
            )
        ) {
            let resolvedTask = recommendation.taskID.flatMap { id in activeTasks.first(where: { $0.id == id }) } ?? task
            return BrainHeroPresentation(
                task: resolvedTask,
                title: UserFacingCopy.sanitize(recommendation.headline),
                supportingLine: UserFacingCopy.sanitize(recommendation.supportingLine),
                scheduledLabel: scheduledLabel(for: resolvedTask, calendar: calendar),
                durationMinutes: recommendation.durationMinutes > 0 ? recommendation.durationMinutes : resolvedTask?.estimatedMinutes,
                whyReasons: Array(recommendation.whyNowReasons.prefix(4)),
                buttonLabel: UserFacingCopy.sanitize(recommendation.buttonLabel),
                isPastDue: isPastDue(task: resolvedTask, now: now, calendar: calendar),
                kind: resolvedTask.map { LifeTimelinePresenter.kindForTask($0) } ?? .personal
            )
        }

        guard let task else {
            return BrainHeroPresentation(
                task: nil,
                title: "You're clear for now",
                supportingLine: "Capture a thought or pick one small win when you're ready.",
                scheduledLabel: nil,
                durationMinutes: nil,
                whyReasons: [],
                buttonLabel: "Capture a thought",
                isPastDue: false,
                kind: .personal
            )
        }

        let semantics = SemanticDecisionBuilder.from(task: task, healthSummary: nil)
        return BrainHeroPresentation(
            task: task,
            title: HumanLanguage.outcomeHeadline(task: task),
            supportingLine: HumanLanguage.recommendationSummary(from: semantics),
            scheduledLabel: scheduledLabel(for: task, calendar: calendar),
            durationMinutes: task.estimatedMinutes > 0 ? task.estimatedMinutes : nil,
            whyReasons: [],
            buttonLabel: "Start",
            isPastDue: isPastDue(task: task, now: now, calendar: calendar),
            kind: LifeTimelinePresenter.kindForTask(task)
        )
    }

    private static func headline(from hero: HeroBriefing, task: LifeTask?) -> String {
        if !hero.actionLine.isEmpty {
            return UserFacingCopy.sanitize(hero.actionLine)
        }
        if let task {
            return HumanLanguage.outcomeHeadline(task: task)
        }
        return "Pick up where you left off"
    }

    private static func supportingLine(
        from hero: HeroBriefing,
        flowSurface: FlowSurface?,
        task: LifeTask?
    ) -> String {
        var parts: [String] = []
        if let context = hero.contextLine, !context.isEmpty {
            parts.append(UserFacingCopy.sanitize(context))
        }
        if !hero.supportingLine.isEmpty {
            parts.append(UserFacingCopy.sanitize(hero.supportingLine))
        }
        if parts.isEmpty, let line = flowSurface?.briefingLines.first {
            parts.append(UserFacingCopy.sanitize(line))
        }
        if parts.isEmpty, let reasoning = flowSurface?.prediction?.reasoning {
            parts.append(UserFacingCopy.sanitize(reasoning))
        }
        if parts.isEmpty, let task {
            parts.append(capacityFitLine(for: task))
        }
        return parts.joined(separator: " ")
    }

    private static func capacityFitLine(for task: LifeTask) -> String {
        if task.estimatedMinutes <= 15 { return "Short win — easy to start." }
        if task.estimatedMinutes >= 60 { return "Block out focus time for this one." }
        return "Fits your current window."
    }

    private static func durationMinutes(
        from hero: HeroBriefing,
        task: LifeTask?,
        flowSurface: FlowSurface?
    ) -> Int? {
        if hero.durationEstimate.pointMinutes > 0 { return hero.durationEstimate.pointMinutes }
        if let minutes = flowSurface?.prediction?.suggestedDurationMinutes, minutes > 0 { return minutes }
        if let task, task.estimatedMinutes > 0 { return task.estimatedMinutes }
        return nil
    }

    private static func scheduledLabel(for task: LifeTask?, calendar: Calendar) -> String? {
        guard let task else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        if let time = task.scheduledTime {
            return formatter.string(from: time)
        }
        if let date = task.scheduledDate, calendar.isDateInToday(date) {
            return "Today"
        }
        return nil
    }

    private static func isPastDue(task: LifeTask?, now: Date, calendar: Calendar) -> Bool {
        guard let task else { return false }
        return TaskHeroEligibility.isPastWindow(for: task, now: now, calendar: calendar)
    }

    // MARK: - Backup

    private static func backupTasks(
        excludingHeroID: String?,
        from tasks: [LifeTask],
        capacity: ExecutiveCapacityState
    ) -> [LifeTask] {
        let candidates = tasks.filter { task in
            guard task.status.isActive else { return false }
            if let excludingHeroID, task.id == excludingHeroID { return false }
            return true
        }

        let sorted: [LifeTask]
        switch capacity.band {
        case .lowCapacity, .recoveryMode:
            sorted = candidates.sorted {
                if $0.estimatedMinutes != $1.estimatedMinutes { return $0.estimatedMinutes < $1.estimatedMinutes }
                return $0.priority > $1.priority
            }
        default:
            sorted = candidates.sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.estimatedMinutes < $1.estimatedMinutes
            }
        }
        return Array(sorted.prefix(2))
    }

    // MARK: - Resume

    private static func buildResume(
        _ snapshot: ResumeSnapshot?,
        now: Date,
        calendar: Calendar
    ) -> BrainResumePresentation? {
        guard let snapshot, !snapshot.isStale else { return nil }
        guard let detail = snapshot.resumeDetail, !detail.isEmpty else { return nil }

        let title = snapshot.lastTaskTitle ?? snapshot.workingContext?.title ?? "Continue where you left off"
        let elapsed: String?
        if let seconds = snapshot.lastTimerElapsedSeconds, seconds > 0 {
            elapsed = "\(max(1, seconds / 60)) min in"
        } else {
            elapsed = nil
        }

        let pausedAgo: String?
        let interval = now.timeIntervalSince(snapshot.savedAt)
        if interval > 120 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            pausedAgo = "paused \(formatter.localizedString(for: snapshot.savedAt, relativeTo: now))"
        } else {
            pausedAgo = nil
        }

        return BrainResumePresentation(
            title: title,
            detail: detail,
            elapsedLabel: elapsed,
            pausedAgoLabel: pausedAgo,
            taskID: snapshot.lastTaskID ?? snapshot.lastTimerTaskID
        )
    }

    // MARK: - Capacity

    private static func buildCapacity(
        executiveCapacity: ExecutiveCapacityState,
        lifeSnapshot: LifeContextSnapshot?,
        healthSummary: HealthSummary?,
        cognitiveSnapshot: CognitiveSnapshot?
    ) -> BrainCapacityPresentation {
        var freeLabel: String?
        if let minutes = lifeSnapshot?.availableTimeMinutes, minutes > 0 {
            freeLabel = "\(minutes) min free"
        }

        var sleepLabel: String?
        if let sleepMin = healthSummary?.totalSleepMinutes, sleepMin > 0 {
            sleepLabel = String(format: "Sleep %.1fh", Double(sleepMin) / 60.0)
        } else if let debt = cognitiveSnapshot?.sleepDebtHours, debt > 0 {
            sleepLabel = String(format: "Sleep debt %.1fh", debt)
        }

        return BrainCapacityPresentation(
            bandLabel: executiveCapacity.band.displayLabel,
            tagline: executiveCapacity.band.tagline,
            freeMinutesLabel: freeLabel,
            sleepLabel: sleepLabel
        )
    }

    // MARK: - Heads up

    private static func buildHeadsUp(
        medications: [Medication],
        bills: [BillItem],
        timelineItems: [LifeTimelineEvent],
        now: Date,
        calendar: Calendar
    ) -> [BrainHeadsUpItem] {
        var items: [BrainHeadsUpItem] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        for med in medications where !med.isTaken && calendar.isDateInToday(med.scheduledTime) {
            items.append(
                BrainHeadsUpItem(
                    id: "med-\(med.id)",
                    kind: .medication,
                    title: med.name,
                    subtitle: "Due \(formatter.string(from: med.scheduledTime))",
                    actionLabel: "Mark taken",
                    medicationID: med.id
                )
            )
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        for bill in bills where !bill.isPaid {
            guard bill.dueDate <= tomorrow || bill.isOverdue else { continue }
            items.append(
                BrainHeadsUpItem(
                    id: "bill-\(bill.id)",
                    kind: .bill,
                    title: bill.title,
                    subtitle: bill.isOverdue ? "Overdue" : "Due soon"
                )
            )
        }

        for item in timelineItems where item.kind == .meeting && !item.isCompleted {
            let delta = item.date.timeIntervalSince(now)
            guard delta > 0, delta <= 3600 else { continue }
            let minutes = max(1, Int(delta / 60))
            items.append(
                BrainHeadsUpItem(
                    id: "cal-\(item.id)",
                    kind: .calendar,
                    title: item.title,
                    subtitle: "In \(minutes) min"
                )
            )
        }

        return Array(items.prefix(3))
    }

    private static func flowWindowLabel(flowSurface: FlowSurface?) -> String? {
        guard let interval = flowSurface?.flowWindow else { return nil }
        let label = FocusWindowFormatter.displayLabel(for: interval)
        return label == FocusWindowFormatter.noStrongWindow ? nil : label
    }

    private static func confidenceLabel(from hero: HeroBriefing?) -> String? {
        guard let hero else { return nil }
        switch hero.confidenceLevel {
        case .high: return nil
        case .medium: return "Moderate confidence"
        case .low: return "Low confidence — tap Why for details"
        }
    }
}
