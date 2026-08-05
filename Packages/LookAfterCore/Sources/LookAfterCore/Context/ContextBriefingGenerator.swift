import Foundation

/// Builds plain-language hero briefings — merged copy, collapsed reasons, adaptive moments.
public struct ContextBriefingGenerator: Sendable {
    private let calendar: Calendar
    private let continueEngine = ContinueRelevanceEngine()
    private let durationEstimator = DurationEstimator()
    private let storyGenerator = TodaysStoryGenerator()

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public struct GenerationContext: Sendable {
        public var upcomingBills: [BillItem]
        public var timelineItems: [LifeTimelineEvent]
        public var isWeekend: Bool
        public var tasks: [LifeTask]
        public var healthSummary: HealthSummary?
        public var completedTaskIDs: Set<String>
        public var flowConfidenceScore: Double?

        public init(
            upcomingBills: [BillItem] = [],
            timelineItems: [LifeTimelineEvent] = [],
            isWeekend: Bool = false,
            tasks: [LifeTask] = [],
            healthSummary: HealthSummary? = nil,
            completedTaskIDs: Set<String> = [],
            flowConfidenceScore: Double? = nil
        ) {
            self.upcomingBills = upcomingBills
            self.timelineItems = timelineItems
            self.isWeekend = isWeekend
            self.tasks = tasks
            self.healthSummary = healthSummary
            self.completedTaskIDs = completedTaskIDs
            self.flowConfidenceScore = flowConfidenceScore
        }
    }

    public func generate(
        from snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        userName: String = "",
        now: Date = Date(),
        peakStartHour: Int = 9,
        context: GenerationContext = GenerationContext()
    ) -> ContextBriefing {
        let dayType = ContextualMomentsBuilder.resolveDayType(
            snapshot: snapshot,
            upcomingBills: context.upcomingBills,
            isWeekend: context.isWeekend,
            now: now
        )
        let scrollMoments = ContextualMomentsBuilder.buildScrollMoments(
            snapshot: snapshot,
            upcomingBills: context.upcomingBills,
            dayType: dayType
        )

        let story = storyGenerator.generate(
            TodaysStoryGenerator.Input(
                snapshot: snapshot,
                tasks: context.tasks,
                timelineItems: context.timelineItems,
                healthSummary: context.healthSummary,
                userName: userName,
                now: now
            )
        )

        let insights = buildInsights(snapshot: snapshot, health: context.healthSummary)
        let continueInput = ContinueRelevanceEngine.Input(
            resume: resume,
            snapshot: snapshot,
            heroTask: snapshot.currentMission,
            completedTaskIDs: context.completedTaskIDs,
            now: now
        )
        let continueDecision = continueEngine.evaluate(continueInput)

        let core = buildCore(
            from: snapshot,
            resume: resume,
            now: now,
            peakStartHour: peakStartHour,
            continueDecision: continueDecision,
            context: context,
            insights: insights
        )

        let confidence = resolveConfidence(
            core: core,
            snapshot: snapshot,
            flowScore: context.flowConfidenceScore,
            insights: insights
        )

        let hero = HeroBriefing(
            greeting: greeting(userName: userName, now: now),
            contextLine: buildContextLine(
                snapshot: snapshot,
                resume: resume,
                core: core,
                continueDecision: continueDecision,
                now: now,
                peakStartHour: peakStartHour
            ),
            actionLine: core.actionLine,
            supportingLine: core.supportingLine,
            outcomeLine: core.outcome,
            whyNowReasons: core.reasons,
            buttonLabel: core.buttonLabel,
            action: core.action,
            dayType: dayType,
            contextualMoments: scrollMoments,
            dayPreview: [],
            confidenceScore: confidence.score,
            confidenceLevel: confidence.level,
            durationEstimate: core.durationEstimate,
            insights: insights,
            lowConfidencePrompt: confidence.lowPrompt,
            planReadyLine: story.isReady ? "Your day is ready." : nil
        )

        return ContextBriefing(hero: hero, todaysStory: story, generatedAt: now)
    }

    private struct CoreRecommendation {
        var actionLine: String
        var supportingLine: String
        var durationEstimate: DurationEstimate
        var outcome: String
        var reasons: [String]
        var buttonLabel: String
        var action: ContextAction
        var impactLabel: String?
        var clarityLabel: String?
    }

    private struct ConfidenceBundle {
        var score: Double
        var level: RecommendationConfidenceLevel
        var lowPrompt: String?
    }

    private func buildCore(
        from snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        now: Date,
        peakStartHour: Int,
        continueDecision: ContinueRelevanceDecision,
        context: GenerationContext,
        insights: [RecommendationInsight]
    ) -> CoreRecommendation {
        switch continueDecision {
        case .askUser(let prompt, _):
            return lowConfidenceCore(prompt: prompt, snapshot: snapshot, resume: resume, context: context)
        case .freshStart:
            if let session = snapshot.lastWorkingContext, session.kind == .focusSession,
               let taskID = session.taskID {
                return inFlowCore(snapshot: snapshot, title: session.title, taskID: taskID, resume: resume, health: context.healthSummary)
            }
        case .continueWork(let working, let reasons):
            if let task = resolveTask(for: working, tasks: context.tasks, snapshot: snapshot) {
                return continueCore(
                    working: working,
                    task: task,
                    snapshot: snapshot,
                    resume: resume,
                    health: context.healthSummary,
                    reasons: reasons
                )
            }
            return continueContextCore(
                working: working,
                snapshot: snapshot,
                resume: resume,
                health: context.healthSummary,
                reasons: reasons,
                tasks: context.tasks
            )
        }

        if snapshot.location == .grocery, snapshot.unpurchasedShoppingCount > 0 {
            return groceryCore(count: snapshot.unpurchasedShoppingCount)
        }

        if let urgent = morningPriorityTask(snapshot: snapshot, tasks: context.tasks, now: now) {
            return priorityCore(task: urgent, snapshot: snapshot, resume: resume, health: context.healthSummary, tasks: context.tasks, now: now)
        }

        if snapshot.sleepQuality == .poor || snapshot.sleepQuality == .fair,
           isBeforePeak(now: now, peakStartHour: peakStartHour),
           snapshot.currentMission == nil {
            return poorSleepCore(now: now, peakStartHour: peakStartHour, snapshot: snapshot, health: context.healthSummary, insights: insights, tasks: context.tasks)
        }

        if let task = snapshot.currentMission,
           TaskHeroEligibility.isEligible(for: task, now: now, calendar: calendar, allTasks: context.tasks) {
            let schedContext = TaskSemanticScheduler.Context(
                now: now,
                energyScore: snapshot.currentEnergy,
                sleepHours: context.healthSummary?.totalSleepMinutes.map { $0 / 60.0 },
                freeBlockMinutes: snapshot.availableTimeMinutes,
                calendar: calendar
            )
            let profile = task.resolvedSemanticProfile
            if profile.semanticType == .medication,
               !TaskSemanticScheduler.schedulability(profile: profile, context: schedContext).isAllowed {
                if let alternate = ExecutiveRecommendationEngine.nextSchedulableTask(
                    excluding: task.id,
                    from: ExecutiveRecommendationEngine.Input(
                        task: nil,
                        snapshot: snapshot,
                        resume: resume,
                        healthSummary: context.healthSummary,
                        tasks: context.tasks,
                        now: now,
                        calendar: calendar
                    ),
                    context: schedContext
                ) {
                    return taskCore(task: alternate, snapshot: snapshot, resume: resume, health: context.healthSummary, isContinue: false, tasks: context.tasks, now: now)
                }
                if let blocked = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
                    task: task,
                    snapshot: snapshot,
                    resume: resume,
                    healthSummary: context.healthSummary,
                    tasks: context.tasks,
                    now: now,
                    calendar: calendar
                )) {
                    return coreFromEngine(blocked, fallbackTask: task)
                }
            }
            return taskCore(task: task, snapshot: snapshot, resume: resume, health: context.healthSummary, isContinue: false, tasks: context.tasks, now: now)
        }

        if let pending = pickBestPendingTask(
            snapshot: snapshot,
            resume: resume,
            context: context,
            now: now
        ) {
            return taskCore(
                task: pending,
                snapshot: snapshot,
                resume: resume,
                health: context.healthSummary,
                isContinue: false,
                tasks: context.tasks,
                now: now
            )
        }

        return idleCore(snapshot: snapshot)
    }

    private func pickBestPendingTask(
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        context: GenerationContext,
        now: Date
    ) -> LifeTask? {
        let active = context.tasks.filter(\.status.isActive)
        guard !active.isEmpty else { return nil }

        if let overdue = active.filter(\.isOverdue).min(by: { $0.priority > $1.priority }) {
            return overdue
        }

        let schedContext = TaskSemanticScheduler.Context(
            now: now,
            energyScore: snapshot.currentEnergy,
            sleepHours: context.healthSummary?.totalSleepMinutes.map { $0 / 60.0 },
            freeBlockMinutes: snapshot.availableTimeMinutes,
            calendar: calendar
        )

        if let recommended = ExecutiveRecommendationEngine.nextSchedulableTask(
            excluding: nil,
            from: ExecutiveRecommendationEngine.Input(
                task: nil,
                snapshot: snapshot,
                resume: resume,
                healthSummary: context.healthSummary,
                tasks: active,
                now: now,
                calendar: calendar
            ),
            context: schedContext
        ) {
            return recommended
        }

        return active
            .filter {
                TaskHeroEligibility.isEligible(
                    for: $0,
                    now: now,
                    calendar: calendar,
                    allTasks: active
                )
            }
            .min {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.estimatedMinutes < $1.estimatedMinutes
            }
    }

    private func continueCore(
        working: WorkingContext,
        task: LifeTask,
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        health: HealthSummary?,
        reasons: [String]
    ) -> CoreRecommendation {
        if let rec = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: task,
            snapshot: snapshot,
            resume: resume,
            healthSummary: health,
            tasks: [],
            now: Date(),
            calendar: calendar,
            isContinue: true
        )) {
            var core = coreFromEngine(rec, fallbackTask: task)
            core.reasons = reasons + core.reasons
            return core
        }

        let priorMinutes = (resume?.lastTimerElapsedSeconds ?? 0) / 60
        let estimate = durationEstimator.estimate(
            DurationEstimator.Input(task: task, snapshot: snapshot, healthSummary: health, priorElapsedMinutes: priorMinutes)
        )
        let headline = objectiveHeadline(task: task, snapshot: snapshot, resume: resume, health: health)
        return CoreRecommendation(
            actionLine: headline,
            supportingLine: HumanLanguage.defaultWhyNow(),
            durationEstimate: estimate,
            outcome: "",
            reasons: reasons + whyNow(for: task, snapshot: snapshot),
            buttonLabel: HumanLanguage.actionButtonLabel(headline: headline, objectKind: .genericTask, isContinue: true),
            action: ContextAction(
                label: headline,
                taskID: task.id,
                kind: .openContinueSession
            )
        )
    }

    private func continueContextCore(
        working: WorkingContext,
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        health: HealthSummary?,
        reasons: [String],
        tasks: [LifeTask]
    ) -> CoreRecommendation {
        let priorMinutes = (resume?.lastTimerElapsedSeconds ?? 0) / 60
        let estimate = durationEstimator.estimate(
            DurationEstimator.Input(snapshot: snapshot, healthSummary: health, title: working.title, priorElapsedMinutes: priorMinutes)
        )
        let resolvedTask = resolveTask(for: working, tasks: tasks, snapshot: snapshot)
        let headline = objectiveHeadline(
            task: resolvedTask,
            snapshot: snapshot,
            resume: resume,
            health: health,
            working: working
        )
        return CoreRecommendation(
            actionLine: headline,
            supportingLine: HumanLanguage.defaultWhyNow(),
            durationEstimate: estimate,
            outcome: "",
            reasons: reasons,
            buttonLabel: HumanLanguage.actionButtonLabel(headline: headline, objectKind: .genericTask, isContinue: true),
            action: ContextAction(label: headline, taskID: working.taskID, kind: .openContinueSession)
        )
    }

    private func taskCore(
        task: LifeTask,
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        health: HealthSummary?,
        isContinue: Bool,
        tasks: [LifeTask] = [],
        now: Date = Date()
    ) -> CoreRecommendation {
        if let rec = ExecutiveRecommendationEngine.recommend(from: ExecutiveRecommendationEngine.Input(
            task: task,
            snapshot: snapshot,
            resume: resume,
            healthSummary: health,
            tasks: tasks,
            now: now,
            calendar: calendar,
            isContinue: isContinue
        )) {
            return coreFromEngine(rec, fallbackTask: task)
        }

        let priorMinutes = isContinue ? (resume?.lastTimerElapsedSeconds ?? 0) / 60 : 0
        let estimate = durationEstimator.estimate(
            DurationEstimator.Input(task: task, snapshot: snapshot, healthSummary: health, priorElapsedMinutes: priorMinutes)
        )
        let headline = objectiveHeadline(task: task, snapshot: snapshot, resume: resume, health: health)
        let decision = SemanticDecisionBuilder.from(task: task, snapshot: snapshot, healthSummary: health)
        return CoreRecommendation(
            actionLine: headline,
            supportingLine: HumanLanguage.defaultWhyNow(),
            durationEstimate: estimate,
            outcome: "",
            reasons: whyNow(for: task, snapshot: snapshot),
            buttonLabel: HumanLanguage.actionButtonLabel(
                headline: headline,
                objectKind: decision.object.kind,
                isContinue: isContinue
            ),
            action: ContextAction(
                label: headline,
                taskID: task.id,
                kind: isContinue ? .openContinueSession : .beginWork
            )
        )
    }

    private func coreFromEngine(_ rec: ExecutiveRecommendationEngine.Output, fallbackTask: LifeTask) -> CoreRecommendation {
        let estimate = DurationEstimate(pointMinutes: rec.durationMinutes, confidence: 0.85)
        return CoreRecommendation(
            actionLine: rec.headline,
            supportingLine: rec.supportingLine,
            durationEstimate: estimate,
            outcome: "",
            reasons: rec.whyNowReasons,
            buttonLabel: rec.buttonLabel,
            action: ContextAction(
                label: rec.headline,
                taskID: rec.taskID ?? fallbackTask.id,
                kind: rec.actionKind
            ),
            impactLabel: rec.impactLabel,
            clarityLabel: rec.clarityLabel
        )
    }

    private func priorityCore(
        task: LifeTask,
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        health: HealthSummary?,
        tasks: [LifeTask],
        now: Date
    ) -> CoreRecommendation {
        var core = taskCore(task: task, snapshot: snapshot, resume: resume, health: health, isContinue: false, tasks: tasks, now: now)
        core.reasons.insert(HumanLanguage.priorityImpact(task: task, snapshot: snapshot), at: 0)
        return core
    }

    private func inFlowCore(
        snapshot: LifeContextSnapshot,
        title: String,
        taskID: String,
        resume: ResumeSnapshot?,
        health: HealthSummary?
    ) -> CoreRecommendation {
        let task = snapshot.currentMission
        let priorMinutes = (resume?.lastTimerElapsedSeconds ?? 0) / 60
        let estimate = durationEstimator.estimate(
            DurationEstimator.Input(task: task, snapshot: snapshot, healthSummary: health, title: title, priorElapsedMinutes: priorMinutes)
        )
        let resolvedTask = task ?? snapshot.currentMission
        let headline = objectiveHeadline(
            task: resolvedTask,
            snapshot: snapshot,
            resume: resume,
            health: health,
            working: WorkingContext(kind: .focusSession, title: title, taskID: taskID)
        )
        return CoreRecommendation(
            actionLine: headline,
            supportingLine: HumanLanguage.continueContextImpact(
                elapsedHours: Double(priorMinutes) / 60.0,
                snapshot: snapshot
            ),
            durationEstimate: estimate,
            outcome: "",
            reasons: whyNow(for: task, snapshot: snapshot),
            buttonLabel: HumanLanguage.actionButtonLabel(headline: headline, objectKind: .genericTask, isContinue: true),
            action: ContextAction(label: headline, taskID: taskID, kind: .openContinueSession)
        )
    }

    private func groceryCore(count: Int) -> CoreRecommendation {
        CoreRecommendation(
            actionLine: "Finish what's on your shopping list",
            supportingLine: "You're at the store now.",
            durationEstimate: DurationEstimate(pointMinutes: 10, confidence: 0.8),
            outcome: "",
            reasons: ["You're at the store now", "\(count) item\(count == 1 ? "" : "s") left"],
            buttonLabel: "Finish the shopping",
            action: ContextAction(label: "Finish the shopping", kind: .openShopping)
        )
    }

    private func poorSleepCore(
        now: Date,
        peakStartHour: Int,
        snapshot: LifeContextSnapshot,
        health: HealthSummary?,
        insights: [RecommendationInsight],
        tasks: [LifeTask]
    ) -> CoreRecommendation {
        if let task = snapshot.currentMission, !isBeforePeak(now: now, peakStartHour: peakStartHour) {
            return taskCore(task: task, snapshot: snapshot, resume: nil, health: health, isContinue: false, tasks: tasks, now: now)
        }
        let waitLabel = poorSleepWaitLabel(now: now, peakStartHour: peakStartHour)
        let estimate = DurationEstimate(pointMinutes: 10, rangeMinMinutes: 5, rangeMaxMinutes: 15, confidence: 0.55)
        return CoreRecommendation(
            actionLine: "One small win",
            supportingLine: HumanLanguage.poorSleepImpact(waitUntil: waitLabel),
            durationEstimate: estimate,
            outcome: "",
            reasons: [HumanLanguage.poorSleepImpact(waitUntil: waitLabel)],
            buttonLabel: "Find something small",
            action: ContextAction(label: "Find something small", kind: .openBrain)
        )
    }

    private func lowConfidenceCore(
        prompt: String,
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        context: GenerationContext
    ) -> CoreRecommendation {
        if let task = snapshot.currentMission {
            return taskCore(task: task, snapshot: snapshot, resume: resume, health: context.healthSummary, isContinue: false, tasks: context.tasks, now: Date())
        }
        return CoreRecommendation(
            actionLine: "Not sure what fits best",
            supportingLine: "I need a little more context before I'm confident.",
            durationEstimate: DurationEstimate(pointMinutes: 15, rangeMinMinutes: 10, rangeMaxMinutes: 30, confidence: 0.45),
            outcome: "",
            reasons: ["I need a little more context before I'm confident"],
            buttonLabel: "Map out your day",
            action: ContextAction(label: "Map out your day", kind: .viewPlan)
        )
    }

    private func idleCore(snapshot: LifeContextSnapshot) -> CoreRecommendation {
        CoreRecommendation(
            actionLine: "Got something on your mind?",
            supportingLine: freeTimeReason(snapshot) ?? "Nothing pressing right now.",
            durationEstimate: DurationEstimate(pointMinutes: 2, confidence: 0.9),
            outcome: "",
            reasons: [freeTimeReason(snapshot), "Nothing pressing right now"].compactMap { $0 },
            buttonLabel: "Remember this",
            action: ContextAction(label: "Remember this", kind: .openBrain)
        )
    }

    private func morningPriorityTask(snapshot: LifeContextSnapshot, tasks: [LifeTask], now: Date) -> LifeTask? {
        guard calendar.component(.hour, from: now) < 12 else { return nil }
        let candidates = tasks.filter { $0.status.isActive }
        if let overdue = candidates.first(where: { $0.isOverdue }) { return overdue }
        if let event = snapshot.calendarAvailability.nextEventTitle,
           let mins = snapshot.calendarAvailability.minutesUntilNextEvent,
           mins <= 180, mins > 15 {
            return candidates.first { task in
                task.title.localizedCaseInsensitiveContains(event) || event.localizedCaseInsensitiveContains(task.title)
            } ?? candidates.first
        }
        return nil
    }

    private func resolveTask(for working: WorkingContext, tasks: [LifeTask], snapshot: LifeContextSnapshot) -> LifeTask? {
        if let id = working.taskID, let match = tasks.first(where: { $0.id == id }) { return match }
        if let mission = snapshot.currentMission, mission.title == working.title { return mission }
        return tasks.first { $0.title == working.title }
    }

    private func buildInsights(snapshot: LifeContextSnapshot, health: HealthSummary?) -> [RecommendationInsight] {
        var items: [RecommendationInsight] = []
        if let sleep = InsightBuilder.sleepInsight(snapshot: snapshot, health: health) {
            items.append(sleep)
        }
        if let cal = InsightBuilder.calendarInsight(snapshot: snapshot) {
            items.append(cal)
        }
        return items
    }

    private func resolveConfidence(
        core: CoreRecommendation,
        snapshot: LifeContextSnapshot,
        flowScore: Double?,
        insights: [RecommendationInsight]
    ) -> ConfidenceBundle {
        var score = flowScore ?? core.durationEstimate.confidence
        if snapshot.sleepQuality == .unknown { score -= 0.08 }
        if snapshot.calendarAvailability.nextEventTitle == nil { score -= 0.04 }
        if core.action.kind == .viewPlan { score = min(score, 0.55) }
        score = min(max(score, 0.25), 0.98)
        let level = RecommendationConfidenceLevel(score: score)
        let lowPrompt: String? = level == .low ? "Not sure what fits best right now." : nil
        return ConfidenceBundle(score: score, level: level, lowPrompt: lowPrompt)
    }

    private func buildContextLine(
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        core: CoreRecommendation,
        continueDecision: ContinueRelevanceDecision,
        now: Date,
        peakStartHour: Int
    ) -> String? {
        if let mins = snapshot.calendarAvailability.minutesUntilNextEvent,
           mins > 0, mins <= 180,
           let event = snapshot.calendarAvailability.nextEventTitle {
            return HumanLanguage.meetingContext(minutes: mins, event: event)
        }

        switch continueDecision {
        case .continueWork:
            return nil
        case .freshStart(let reason):
            if calendar.component(.hour, from: now) < 12, reason.contains("New day") {
                return nil
            }
        case .askUser:
            return nil
        }

        if snapshot.sleepQuality == .poor || snapshot.sleepQuality == .fair,
           isBeforePeak(now: now, peakStartHour: peakStartHour),
           let wait = poorSleepWaitLabel(now: now, peakStartHour: peakStartHour) {
            return HumanLanguage.poorSleepImpact(waitUntil: wait)
        }
        if snapshot.location == .grocery, snapshot.unpurchasedShoppingCount > 0 {
            return "You're at the store now."
        }
        return nil
    }

    private func whyNow(for task: LifeTask?, snapshot: LifeContextSnapshot) -> [String] {
        var reasons: [String] = []
        if let free = freeTimeReason(snapshot) { reasons.append(free) }
        if let task, let deadline = task.deadline {
            reasons.append(HumanLanguage.deadlineImpact(deadline: deadline, snapshot: snapshot, calendar: calendar))
        }
        if let task, task.progress > 0 {
            reasons.append(HumanLanguage.progressImpact(fraction: task.progress))
        }
        if let mins = snapshot.calendarAvailability.minutesUntilNextEvent, mins > 0, mins <= 120,
           let event = snapshot.calendarAvailability.nextEventTitle {
            reasons.append("You'll have nothing important left before \(event).")
        }
        if snapshot.activeDevices.focusModeEnabled {
            reasons.append(HumanLanguage.focusModeImpact())
        }
        if reasons.isEmpty, task != nil {
            reasons.append(HumanLanguage.defaultWhyNow())
        }
        return Array(reasons.prefix(6))
    }

    private func freeTimeReason(_ snapshot: LifeContextSnapshot) -> String? {
        guard snapshot.availableTimeMinutes > 0, snapshot.availableTimeMinutes < 480 else { return nil }
        return HumanLanguage.freeTimeImpact(minutes: snapshot.availableTimeMinutes)
    }

    private func greeting(userName: String, now: Date) -> String {
        let hour = calendar.component(.hour, from: now)
        let salutation: String
        switch hour {
        case 5..<12: salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        case 17..<22: salutation = "Good evening"
        default: salutation = "Good night"
        }
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? salutation : "\(salutation), \(name)"
    }

    private func isBeforePeak(now: Date, peakStartHour: Int) -> Bool {
        calendar.component(.hour, from: now) < min(max(peakStartHour, 5), 23)
    }

    private func poorSleepWaitLabel(now: Date, peakStartHour: Int) -> String? {
        let currentHour = calendar.component(.hour, from: now)
        let clampedPeak = min(max(peakStartHour, 5), 23)
        guard currentHour < clampedPeak else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = clampedPeak
        components.minute = 0
        guard let target = calendar.date(from: components) else { return nil }
        return formatClockTime(target)
    }

    private func formatClockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    private func objectiveHeadline(
        task: LifeTask?,
        snapshot: LifeContextSnapshot,
        resume: ResumeSnapshot?,
        health: HealthSummary?,
        working: WorkingContext? = nil
    ) -> String {
        let context = HeroObjectiveContextBuilder.build(
            task: task,
            snapshot: snapshot,
            resume: resume,
            healthSummary: health,
            workingContext: working
        )
        return HumanLanguage.outcomeHeadline(context: context)
    }
}
