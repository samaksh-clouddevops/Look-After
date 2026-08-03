import Foundation

/// Context-aware executive recommendation — classifies tasks, respects timing windows,
/// recommends preparation steps, and produces non-duplicative copy for the Briefing hero.
public enum ExecutiveRecommendationEngine {

    public struct Input: Sendable {
        public var task: LifeTask?
        public var snapshot: LifeContextSnapshot
        public var resume: ResumeSnapshot?
        public var healthSummary: HealthSummary?
        public var tasks: [LifeTask]
        public var now: Date
        public var calendar: Calendar
        public var isContinue: Bool

        public init(
            task: LifeTask?,
            snapshot: LifeContextSnapshot,
            resume: ResumeSnapshot? = nil,
            healthSummary: HealthSummary? = nil,
            tasks: [LifeTask] = [],
            now: Date = Date(),
            calendar: Calendar = .current,
            isContinue: Bool = false
        ) {
            self.task = task
            self.snapshot = snapshot
            self.resume = resume
            self.healthSummary = healthSummary
            self.tasks = tasks
            self.now = now
            self.calendar = calendar
            self.isContinue = isContinue
        }
    }

    public struct Output: Sendable, Equatable {
        public var headline: String
        public var supportingLine: String
        public var buttonLabel: String
        public var durationMinutes: Int
        public var whyNowReasons: [String]
        public var taskID: String?
        public var actionKind: ContextActionKind
        public var isPreparation: Bool
        public var impactLabel: String?
        public var clarityLabel: String?

        public init(
            headline: String,
            supportingLine: String,
            buttonLabel: String,
            durationMinutes: Int,
            whyNowReasons: [String] = [],
            taskID: String? = nil,
            actionKind: ContextActionKind = .beginWork,
            isPreparation: Bool = false,
            impactLabel: String? = nil,
            clarityLabel: String? = nil
        ) {
            self.headline = headline
            self.supportingLine = supportingLine
            self.buttonLabel = buttonLabel
            self.durationMinutes = durationMinutes
            self.whyNowReasons = whyNowReasons
            self.taskID = taskID
            self.actionKind = actionKind
            self.isPreparation = isPreparation
            self.impactLabel = impactLabel
            self.clarityLabel = clarityLabel
        }
    }

    // MARK: - Public API

    public static func recommend(from input: Input) -> Output? {
        let schedContext = schedulerContext(from: input)

        if let task = input.task {
            if !TaskHeroEligibility.isEligible(
                for: task,
                now: input.now,
                calendar: input.calendar,
                allTasks: input.tasks
            ) {
                if let alternate = nextSchedulableTask(excluding: task.id, from: input, context: schedContext) {
                    return recommend(from: Input(
                        task: alternate,
                        snapshot: input.snapshot,
                        resume: input.resume,
                        healthSummary: input.healthSummary,
                        tasks: input.tasks,
                        now: input.now,
                        calendar: input.calendar,
                        isContinue: false
                    ))
                }
                if let evening = eveningRecommendation(from: input) {
                    return evening
                }
                return nil
            }

            if isMedicationOutOfWindow(task: task, context: schedContext) {
                if let alternate = nextSchedulableTask(excluding: task.id, from: input, context: schedContext) {
                    return recommend(from: Input(
                        task: alternate,
                        snapshot: input.snapshot,
                        resume: input.resume,
                        healthSummary: input.healthSummary,
                        tasks: input.tasks,
                        now: input.now,
                        calendar: input.calendar,
                        isContinue: false
                    ))
                }
                if let evening = eveningRecommendation(from: input) {
                    return evening
                }
                return nil
            }

            if let prep = preparationRecommendation(for: task, input: input) {
                return prep
            }

            return taskRecommendation(for: task, input: input)
        }

        if let alternate = nextSchedulableTask(excluding: nil, from: input, context: schedContext) {
            return recommend(from: Input(
                task: alternate,
                snapshot: input.snapshot,
                resume: input.resume,
                healthSummary: input.healthSummary,
                tasks: input.tasks,
                now: input.now,
                calendar: input.calendar,
                isContinue: false
            ))
        }

        return eveningRecommendation(from: input)
    }

    /// Evening wind-down when nothing else is schedulable — matches reference Briefing hero.
    private static func eveningRecommendation(from input: Input) -> Output? {
        let hour = input.calendar.component(.hour, from: input.now)
        guard hour >= 17 || hour < 5 else { return nil }

        return Output(
            headline: "Plan tomorrow's top 3 priorities",
            supportingLine: "Setting clear priorities tonight helps you start tomorrow with clarity.",
            buttonLabel: "Start now",
            durationMinutes: 15,
            whyNowReasons: ["Nothing pressing right now — tomorrow benefits from a clear plan."],
            taskID: nil,
            actionKind: .viewPlan,
            impactLabel: "High Impact",
            clarityLabel: "Mental Clarity"
        )
    }

    public static func nextSchedulableTask(
        excluding excludedID: String?,
        from input: Input,
        context: TaskSemanticScheduler.Context
    ) -> LifeTask? {
        let active = input.tasks.filter {
            $0.status.isActive
                && $0.id != excludedID
                && TaskHeroEligibility.isEligible(
                    for: $0,
                    now: input.now,
                    calendar: input.calendar,
                    allTasks: input.tasks
                )
        }
        let scored = active.map { task -> (LifeTask, Int) in
            let profile = task.resolvedSemanticProfile
            let schedulable = TaskSemanticScheduler.schedulability(profile: profile, context: context).isAllowed
            var score = TaskSemanticScheduler.schedulingScoreAdjustment(profile: profile, context: context)
            if !schedulable { score -= 500 }
            if task.isOverdue { score += 50 }
            if task.id == input.snapshot.currentMission?.id { score += 30 }
            return (task, score)
        }
        return scored
            .filter { $0.1 > -400 }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

    // MARK: - Medication

    private static func isMedicationOutOfWindow(task: LifeTask, context: TaskSemanticScheduler.Context) -> Bool {
        let profile = task.resolvedSemanticProfile
        guard profile.semanticType == .medication else { return false }
        return !TaskSemanticScheduler.schedulability(profile: profile, context: context).isAllowed
    }

    private static func medicationDisplayName(from task: LifeTask) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !UserFacingCopy.isInternalExecutionLabel(title) {
            return title.lowercased().contains("medication") || title.lowercased().contains("thyroid")
                ? title
                : title
        }
        let corpus = [task.description, task.notes].joined(separator: " ").lowercased()
        if corpus.contains("thyroid") { return "thyroid medication" }
        if corpus.contains("levothyroxine") { return "levothyroxine" }
        return "medication"
    }

    // MARK: - Preparation

    private static func preparationRecommendation(for task: LifeTask, input: Input) -> Output? {
        let profile = task.resolvedSemanticProfile
        let snapshot = input.snapshot
        let now = input.now

        if profile.semanticType == .medication {
            return nil
        }

        if let event = snapshot.calendarAvailability.nextEventTitle,
           let mins = snapshot.calendarAvailability.minutesUntilNextEvent {
            if isMeetingPrepCandidate(task: task, event: event, minutesUntil: mins) {
                let headline = meetingPrepHeadline(event: event, minutesUntil: mins)
                let supporting = "You'll be ready when \(event) starts."
                return Output(
                    headline: headline,
                    supportingLine: supporting,
                    buttonLabel: "I'm ready",
                    durationMinutes: min(5, max(2, mins / 3)),
                    whyNowReasons: [HumanLanguage.meetingContext(minutes: mins, event: event)],
                    taskID: task.id,
                    actionKind: .beginWork,
                    isPreparation: true,
                    impactLabel: "High Impact",
                    clarityLabel: "Mental Clarity"
                )
            }
        }

        if profile.semanticType == .physicalActivity || isExerciseTask(task) {
            if let mins = minutesUntilScheduled(task: task, now: now, calendar: input.calendar), mins > 0, mins <= 60 {
                let headline = exercisePrepHeadline(minutesUntil: mins)
                let leaveIn = max(1, mins - 13)
                let supporting = "Leave home in about \(leaveIn) minute\(leaveIn == 1 ? "" : "s")."
                return Output(
                    headline: headline,
                    supportingLine: supporting,
                    buttonLabel: "I'm ready",
                    durationMinutes: min(8, max(3, mins / 4)),
                    whyNowReasons: ["\(exerciseLabel(task)) starts in \(mins) minutes."],
                    taskID: task.id,
                    actionKind: .beginWork,
                    isPreparation: true,
                    impactLabel: "High Impact",
                    clarityLabel: "Physical"
                )
            }
        }

        if isTravelTask(task), isTomorrow(task: task, now: now, calendar: input.calendar) {
            return Output(
                headline: "Charge your headphones",
                supportingLine: "A small prep step before travel tomorrow.",
                buttonLabel: "Done",
                durationMinutes: 2,
                whyNowReasons: ["\(task.title) is tomorrow — easy wins tonight reduce morning stress."],
                taskID: task.id,
                actionKind: .beginWork,
                isPreparation: true,
                clarityLabel: "Travel"
            )
        }

        return nil
    }

    // MARK: - Task recommendation

    private static func taskRecommendation(for task: LifeTask, input: Input) -> Output {
        let heroContext = HeroObjectiveContextBuilder.build(
            task: task,
            snapshot: input.snapshot,
            resume: input.resume,
            healthSummary: input.healthSummary
        )
        let headline = HumanLanguage.outcomeHeadline(context: heroContext)
        let estimate = DurationEstimator().estimate(
            DurationEstimator.Input(
                task: task,
                snapshot: input.snapshot,
                healthSummary: input.healthSummary,
                priorElapsedMinutes: input.isContinue ? (input.resume?.lastTimerElapsedSeconds ?? 0) / 60 : 0
            )
        )
        let profile = task.resolvedSemanticProfile
        let decision = SemanticDecisionBuilder.from(task: task, snapshot: input.snapshot, healthSummary: input.healthSummary)
        let rendered = HumanLanguage.render(decision, snapshot: input.snapshot)

        var whyNow = buildWhyNow(for: task, snapshot: input.snapshot, calendar: input.calendar)
        let supporting = distinctSupporting(
            headline: headline,
            contextLine: rendered.benefitLine,
            whyNow: whyNow
        )

        let button = HumanLanguage.actionButtonLabel(
            headline: headline,
            objectKind: decision.object.kind,
            isContinue: input.isContinue,
            isPreparation: false
        )

        return Output(
            headline: headline,
            supportingLine: supporting,
            buttonLabel: button,
            durationMinutes: estimate.pointMinutes,
            whyNowReasons: whyNow,
            taskID: task.id,
            actionKind: input.isContinue ? .openContinueSession : .beginWork,
            isPreparation: false,
            impactLabel: impactLabel(for: profile, task: task),
            clarityLabel: clarityLabel(for: profile)
        )
    }

    // MARK: - Copy helpers

    private static func distinctSupporting(headline: String, contextLine: String, whyNow: [String]) -> String {
        let headlineKey = headline.lowercased()
        if let why = whyNow.first, !why.isEmpty, !isDuplicate(why, of: headlineKey) {
            return CalmHeroContentBuilder.firstSentence(why)
        }
        if !contextLine.isEmpty, !isDuplicate(contextLine, of: headlineKey) {
            return CalmHeroContentBuilder.firstSentence(contextLine)
        }
        return defaultSupporting(for: headline)
    }

    private static func isDuplicate(_ text: String, of headlineKey: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == headlineKey { return true }
        if headlineKey.contains(normalized) || normalized.contains(headlineKey) { return true }
        return false
    }

    private static func defaultSupporting(for headline: String) -> String {
        let lower = headline.lowercased()
        if lower.contains("medication") || lower.contains("thyroid") {
            return "Take it on an empty stomach, before breakfast."
        }
        if lower.contains("gym") || lower.contains("workout") {
            return "You'll feel better once you're moving."
        }
        if lower.hasPrefix("review ") || lower.hasPrefix("finish ") {
            return "A focused push now makes the rest of today lighter."
        }
        return "This is the gentlest useful next step."
    }

    private static func buildWhyNow(for task: LifeTask, snapshot: LifeContextSnapshot, calendar: Calendar) -> [String] {
        var reasons: [String] = []
        if let mins = snapshot.calendarAvailability.minutesUntilNextEvent, mins > 0, mins <= 120,
           let event = snapshot.calendarAvailability.nextEventTitle {
            reasons.append(HumanLanguage.meetingContext(minutes: mins, event: event))
        }
        if task.isOverdue {
            reasons.append("Clearing this lifts a weight you've been carrying.")
        }
        if task.progress > 0 {
            reasons.append(HumanLanguage.progressImpact(fraction: task.progress))
        }
        if reasons.isEmpty {
            reasons.append(HumanLanguage.defaultWhyNow())
        }
        return Array(reasons.prefix(4))
    }

    private static func impactLabel(for profile: TaskSemanticProfile, task: LifeTask) -> String? {
        switch profile.consequenceOfDelay {
        case .medicalRisk: return "Health"
        case .high: return "High Impact"
        case .moderate: return task.isOverdue ? "High Impact" : "Medium Impact"
        default:
            if profile.cognitiveRequirement == .deepFocus { return "High Impact" }
            return task.priority == .high ? "High Impact" : nil
        }
    }

    private static func clarityLabel(for profile: TaskSemanticProfile) -> String? {
        switch profile.semanticType {
        case .medication: return "Health"
        case .physicalActivity: return "Physical"
        case .deepWork: return "Mental Clarity"
        case .communication: return "Connection"
        default:
            if profile.cognitiveRequirement == .deepFocus { return "Mental Clarity" }
            return nil
        }
    }

    // MARK: - Prep heuristics

    private static func isMeetingPrepCandidate(task: LifeTask, event: String, minutesUntil: Int) -> Bool {
        guard minutesUntil >= 8, minutesUntil <= 45 else { return false }
        let lower = task.title.lowercased()
        let eventLower = event.lowercased()
        return lower.contains("meeting") || lower.contains(eventLower) || eventLower.contains(lower.prefix(8))
    }

    private static func meetingPrepHeadline(event: String, minutesUntil: Int) -> String {
        if minutesUntil <= 15 { return "Open the meeting notes" }
        return "Review agenda before \(event)"
    }

    private static func isExerciseTask(_ task: LifeTask) -> Bool {
        let lower = [task.title, task.description].joined(separator: " ").lowercased()
        return lower.contains("gym") || lower.contains("workout") || lower.contains("run") || lower.contains("exercise")
    }

    private static func exerciseLabel(_ task: LifeTask) -> String {
        let lower = task.title.lowercased()
        if lower.contains("gym") { return "Gym" }
        return task.title
    }

    private static func exercisePrepHeadline(minutesUntil: Int) -> String {
        if minutesUntil <= 20 { return "Put on workout clothes" }
        return "Fill your water bottle"
    }

    private static func isTravelTask(_ task: LifeTask) -> Bool {
        let lower = [task.title, task.description, task.tags.joined(separator: " ")].joined(separator: " ").lowercased()
        return lower.contains("flight") || lower.contains("travel") || lower.contains("airport") || lower.contains("trip")
    }

    private static func isTomorrow(task: LifeTask, now: Date, calendar: Calendar) -> Bool {
        let target = task.scheduledDate ?? task.deadline ?? task.scheduledTime
        guard let target else { return false }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 99
        return days == 1
    }

    private static func minutesUntilScheduled(task: LifeTask, now: Date, calendar: Calendar) -> Int? {
        guard let scheduled = task.scheduledTime ?? task.scheduledDate else { return nil }
        let interval = scheduled.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        return Int(interval / 60)
    }

    private static func schedulerContext(from input: Input) -> TaskSemanticScheduler.Context {
        TaskSemanticScheduler.Context(
            now: input.now,
            energyScore: input.snapshot.currentEnergy,
            sleepHours: input.healthSummary?.totalSleepMinutes.map { $0 / 60.0 },
            freeBlockMinutes: input.snapshot.availableTimeMinutes,
            calendar: input.calendar
        )
    }
}
