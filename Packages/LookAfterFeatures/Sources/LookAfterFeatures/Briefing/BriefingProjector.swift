import Foundation
import LookAfterCore
import ExecutiveBrain

public struct BriefingProjectorInput: Sendable {
    public var userName: String
    public var heroBriefing: HeroBriefing?
    public var brainDecision: BrainDecision?
    public var flowSurface: FlowSurface?
    public var recommendation: String
    public var topTasks: [LifeTask]
    public var resumeSnapshot: ResumeSnapshot?
    public var executiveCapacity: ExecutiveCapacityState
    public var lifeSnapshot: LifeContextSnapshot?
    public var cognitiveSnapshot: CognitiveSnapshot?
    public var healthSummary: HealthSummary?
    public var activeTasks: [LifeTask]
    public var upcomingBills: [BillItem]
    public var medications: [Medication]
    public var timelineItems: [LifeTimelineEvent]
    public var readinessLabel: String?
    public var now: Date
    public var calendar: Calendar

    public init(
        userName: String,
        heroBriefing: HeroBriefing? = nil,
        brainDecision: BrainDecision? = nil,
        flowSurface: FlowSurface? = nil,
        recommendation: String = "",
        topTasks: [LifeTask] = [],
        resumeSnapshot: ResumeSnapshot? = nil,
        executiveCapacity: ExecutiveCapacityState = .moderate,
        lifeSnapshot: LifeContextSnapshot? = nil,
        cognitiveSnapshot: CognitiveSnapshot? = nil,
        healthSummary: HealthSummary? = nil,
        activeTasks: [LifeTask] = [],
        upcomingBills: [BillItem] = [],
        medications: [Medication] = [],
        timelineItems: [LifeTimelineEvent] = [],
        readinessLabel: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.userName = userName
        self.heroBriefing = heroBriefing
        self.brainDecision = brainDecision
        self.flowSurface = flowSurface
        self.recommendation = recommendation
        self.topTasks = topTasks
        self.resumeSnapshot = resumeSnapshot
        self.executiveCapacity = executiveCapacity
        self.lifeSnapshot = lifeSnapshot
        self.cognitiveSnapshot = cognitiveSnapshot
        self.healthSummary = healthSummary
        self.activeTasks = activeTasks
        self.upcomingBills = upcomingBills
        self.medications = medications
        self.timelineItems = timelineItems
        self.readinessLabel = readinessLabel
        self.now = now
        self.calendar = calendar
    }
}

public struct UnifiedBriefingSurface: Sendable {
    public var greeting: BriefingGreeting
    public var executiveHero: BriefingExecutiveHero?
    public var brainPresentation: BrainPresentation

    public init(
        greeting: BriefingGreeting,
        executiveHero: BriefingExecutiveHero?,
        brainPresentation: BrainPresentation
    ) {
        self.greeting = greeting
        self.executiveHero = executiveHero
        self.brainPresentation = brainPresentation
    }
}

/// Hero display fields shared by Brain tab and Briefing cards.
public struct BriefingHeroDisplayContent: Sendable {
    public var title: String
    public var subtitle: String
    public var whyLine: String?
    public var buttonLabel: String
    public var durationLabel: String?
    public var windowLabel: String?
    public var greeting: String?

    public init(
        title: String,
        subtitle: String,
        whyLine: String? = nil,
        buttonLabel: String,
        durationLabel: String? = nil,
        windowLabel: String? = nil,
        greeting: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.whyLine = whyLine
        self.buttonLabel = buttonLabel
        self.durationLabel = durationLabel
        self.windowLabel = windowLabel
        self.greeting = greeting
    }
}

/// Stateless projector — single priority chain for greeting, hero, and brain presentation.
public enum BriefingProjector {
    public static func project(_ input: BriefingProjectorInput) -> UnifiedBriefingSurface {
        let greeting = projectGreeting(
            userName: input.userName,
            flowSurface: input.flowSurface,
            heroBriefing: input.heroBriefing,
            now: input.now,
            calendar: input.calendar
        )
        let executiveHero = projectExecutiveHero(
            heroBriefing: input.heroBriefing,
            brainDecision: input.brainDecision,
            flowSurface: input.flowSurface,
            recommendation: input.recommendation,
            topTasks: input.topTasks,
            greeting: greeting
        )
        let brainPresentation = BrainPresentationBuilder.build(
            .init(
                heroBriefing: input.heroBriefing,
                resumeSnapshot: input.resumeSnapshot,
                executiveCapacity: input.executiveCapacity,
                lifeSnapshot: input.lifeSnapshot,
                flowSurface: input.flowSurface,
                cognitiveSnapshot: input.cognitiveSnapshot,
                healthSummary: input.healthSummary,
                activeTasks: input.activeTasks,
                upcomingBills: input.upcomingBills,
                medications: input.medications,
                timelineItems: input.timelineItems,
                readinessLabel: input.readinessLabel,
                now: input.now,
                calendar: input.calendar
            )
        )
        return UnifiedBriefingSurface(
            greeting: greeting,
            executiveHero: executiveHero,
            brainPresentation: brainPresentation
        )
    }

    public static func heroDisplayContent(
        from input: BriefingProjectorInput,
        peakFocusWindow: String? = nil
    ) -> BriefingHeroDisplayContent {
        let heroTask = input.flowSurface?.heroTask ?? input.topTasks.first
        let orchestratorHero = input.heroBriefing

        let title: String
        if let hero = orchestratorHero, !hero.actionLine.isEmpty {
            title = UserFacingCopy.sanitize(hero.actionLine)
        } else if let task = heroTask {
            title = HumanLanguage.outcomeHeadline(task: task)
        } else {
            title = "Pick up where you left off"
        }

        let subtitle: String
        if let hero = orchestratorHero {
            var parts: [String] = []
            if let context = hero.contextLine, !context.isEmpty {
                parts.append(UserFacingCopy.sanitize(context))
            }
            if !hero.outcomeLine.isEmpty {
                parts.append(UserFacingCopy.sanitize(hero.outcomeLine))
            }
            if !parts.isEmpty {
                subtitle = parts.joined(separator: " ")
            } else if let line = input.flowSurface?.briefingLines.first {
                subtitle = UserFacingCopy.sanitize(line)
            } else if let reasoning = input.flowSurface?.prediction?.reasoning, !reasoning.isEmpty {
                subtitle = UserFacingCopy.sanitize(reasoning)
            } else {
                subtitle = UserFacingCopy.sanitize(input.recommendation)
            }
        } else if let line = input.flowSurface?.briefingLines.first {
            subtitle = UserFacingCopy.sanitize(line)
        } else if let reasoning = input.flowSurface?.prediction?.reasoning, !reasoning.isEmpty {
            subtitle = UserFacingCopy.sanitize(reasoning)
        } else {
            subtitle = UserFacingCopy.sanitize(input.recommendation)
        }

        let whyLine = orchestratorHero?.primaryWhyLine.map { UserFacingCopy.sanitize($0) }

        let buttonLabel: String
        if let hero = orchestratorHero, !hero.buttonLabel.isEmpty {
            buttonLabel = UserFacingCopy.sanitize(hero.buttonLabel)
        } else if let label = input.flowSurface?.prediction?.buttonLabel {
            buttonLabel = UserFacingCopy.sanitize(label)
        } else if let task = heroTask {
            buttonLabel = HumanLanguage.outcomeHeadline(task: task)
        } else {
            buttonLabel = "Start now"
        }

        let durationLabel: String?
        if let hero = orchestratorHero, hero.durationEstimate.pointMinutes > 0 {
            durationLabel = hero.durationEstimate.displayLabel
        } else if let minutes = input.flowSurface?.prediction?.suggestedDurationMinutes, minutes > 0 {
            durationLabel = UserFacingCopy.actionDurationSubtitle(minutes: minutes)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        } else {
            durationLabel = nil
        }

        let windowLabel: String?
        if let interval = input.flowSurface?.flowWindow {
            let label = FocusWindowFormatter.displayLabel(for: interval)
            windowLabel = label == FocusWindowFormatter.noStrongWindow ? nil : label
        } else if let peak = peakFocusWindow, peak != UserFacingCopy.noFocusWindowToday {
            windowLabel = peak
        } else {
            windowLabel = nil
        }

        return BriefingHeroDisplayContent(
            title: title,
            subtitle: subtitle,
            whyLine: whyLine,
            buttonLabel: buttonLabel,
            durationLabel: durationLabel,
            windowLabel: windowLabel,
            greeting: orchestratorHero?.greeting
        )
    }

    // MARK: - Greeting

    public static func projectGreeting(
        userName: String,
        flowSurface: FlowSurface?,
        heroBriefing: HeroBriefing?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BriefingGreeting {
        let hour = calendar.component(.hour, from: now)
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "Good morning"
        case 12..<17: timeGreeting = "Good afternoon"
        case 17..<21: timeGreeting = "Good evening"
        default: timeGreeting = "Good night"
        }

        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let displayName = name.isEmpty ? "" : name
        let dateLine = now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

        if let heroGreeting = heroBriefing?.greeting, !heroGreeting.isEmpty {
            return greetingFromLine(heroGreeting, displayName: displayName, dateLine: dateLine)
        }

        if let flowGreeting = flowSurface?.greeting, !flowGreeting.isEmpty {
            let hasName = !name.isEmpty && flowGreeting.localizedCaseInsensitiveContains(name)
            if hasName {
                return BriefingGreeting(
                    timeGreeting: flowGreeting.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                    userName: "",
                    dateLine: dateLine
                )
            }
            return BriefingGreeting(
                timeGreeting: flowGreeting.trimmingCharacters(in: CharacterSet(charactersIn: ".!,")),
                userName: displayName,
                dateLine: dateLine
            )
        }

        return BriefingGreeting(timeGreeting: timeGreeting, userName: displayName, dateLine: dateLine)
    }

    // MARK: - Executive hero

    public static func projectExecutiveHero(
        heroBriefing: HeroBriefing?,
        brainDecision: BrainDecision?,
        flowSurface: FlowSurface?,
        recommendation: String,
        topTasks: [LifeTask],
        greeting: BriefingGreeting
    ) -> BriefingExecutiveHero? {
        if let hero = heroBriefing {
            let actionLine = UserFacingCopy.sanitize(hero.actionLine)
            let supporting = UserFacingCopy.sanitize(hero.supportingLine)
            let why = distinctWhyLine(
                supporting: supporting,
                primaryWhy: hero.primaryWhyLine.map { UserFacingCopy.sanitize($0) },
                headline: actionLine
            )
            let narrative = composeNarrative(
                contextLine: hero.contextLine,
                actionLine: actionLine,
                outcomeLine: hero.outcomeLine,
                supportingLine: supporting,
                fallback: recommendation
            )
            let ignoreConsequence = hero.whyNowReasons.dropFirst().first.map { UserFacingCopy.sanitize($0) }
            let duration = hero.durationEstimate.pointMinutes > 0
                ? formatDurationMinutes(hero.durationEstimate.pointMinutes)
                : nil
            let button = UserFacingCopy.sanitize(hero.buttonLabel)

            return BriefingExecutiveHero(
                greeting: UserFacingCopy.sanitize(hero.greeting),
                narrative: narrative,
                actionLine: actionLine,
                whyLine: why,
                buttonLabel: button,
                durationLabel: duration,
                impactLabel: inferImpactLabel(from: hero),
                clarityLabel: inferClarityLabel(from: hero),
                ignoreConsequence: ignoreConsequence,
                alternativeLabel: hero.lowConfidencePrompt.map { UserFacingCopy.sanitize($0) },
                actionKind: hero.action.kind,
                actionTaskID: hero.action.taskID
            )
        }

        if let decision = brainDecision {
            let rendered = IntentRenderer.hero(from: decision.intent, whyNow: decision.whyNow)
            return BriefingExecutiveHero(
                greeting: greetingDisplayLine(from: greeting),
                narrative: UserFacingCopy.sanitize(decision.supportingLine),
                actionLine: UserFacingCopy.sanitize(decision.headline),
                whyLine: decision.whyNow.first.map { UserFacingCopy.sanitize($0) },
                buttonLabel: UserFacingCopy.sanitize(rendered.primaryButton),
                durationLabel: rendered.durationLabel.isEmpty ? nil : rendered.durationLabel
            )
        }

        if let surface = flowSurface {
            let heroTask = surface.heroTask ?? topTasks.first
            let actionLine = heroTask.map { HumanLanguage.outcomeHeadline(task: $0) } ?? "Pick up where you left off"
            let narrative = surface.briefingLines.prefix(2).joined(separator: " ")
            let why = surface.prediction?.reasoning ?? surface.coachMoment?.message

            return BriefingExecutiveHero(
                greeting: greetingDisplayLine(from: greeting),
                narrative: UserFacingCopy.sanitize(narrative.isEmpty ? recommendation : narrative),
                actionLine: UserFacingCopy.sanitize(actionLine),
                whyLine: why.map { UserFacingCopy.sanitize($0) },
                buttonLabel: UserFacingCopy.sanitize(surface.prediction?.buttonLabel ?? actionLine),
                durationLabel: surface.prediction.map {
                    UserFacingCopy.actionDurationSubtitle(minutes: $0.suggestedDurationMinutes)
                }
            )
        }

        return nil
    }

    public static func greetingDisplayLine(from greeting: BriefingGreeting) -> String {
        if greeting.userName.isEmpty {
            return greeting.timeGreeting
        }
        return "\(greeting.timeGreeting), \(greeting.userName)"
    }

    // MARK: - Private helpers

    private static func greetingFromLine(_ source: String, displayName: String, dateLine: String) -> BriefingGreeting {
        let trimmed = source.trimmingCharacters(in: CharacterSet(charactersIn: ".!,"))
        if !displayName.isEmpty, trimmed.localizedCaseInsensitiveContains(displayName) {
            return BriefingGreeting(timeGreeting: trimmed, userName: "", dateLine: dateLine)
        }
        return BriefingGreeting(timeGreeting: trimmed, userName: displayName, dateLine: dateLine)
    }

    private static func composeNarrative(
        contextLine: String?,
        actionLine: String,
        outcomeLine: String?,
        supportingLine: String? = nil,
        fallback: String
    ) -> String {
        var parts: [String] = []
        if let contextLine, !contextLine.isEmpty {
            parts.append(UserFacingCopy.sanitize(contextLine))
        }
        if let outcomeLine, !outcomeLine.isEmpty {
            parts.append(UserFacingCopy.sanitize(outcomeLine))
        }
        if parts.isEmpty, let supportingLine, !supportingLine.isEmpty,
           !UserFacingCopy.isDuplicateCopy(supportingLine, actionLine) {
            parts.append(supportingLine)
        }
        if parts.isEmpty {
            let sanitized = UserFacingCopy.sanitize(fallback)
            if !sanitized.isEmpty, !UserFacingCopy.isGenericMotivation(sanitized),
               !UserFacingCopy.isDuplicateCopy(sanitized, actionLine) {
                parts.append(sanitized)
            }
        }
        return parts.joined(separator: " ")
    }

    private static func distinctWhyLine(supporting: String, primaryWhy: String?, headline: String) -> String? {
        if !supporting.isEmpty, !UserFacingCopy.isDuplicateCopy(supporting, headline) {
            return supporting
        }
        if let primaryWhy, !primaryWhy.isEmpty, !UserFacingCopy.isDuplicateCopy(primaryWhy, headline) {
            return primaryWhy
        }
        return nil
    }

    private static func inferImpactLabel(from hero: HeroBriefing) -> String? {
        if hero.confidenceLevel == .high { return "High Impact" }
        if hero.confidenceLevel == .medium { return "Medium Impact" }
        return nil
    }

    private static func inferClarityLabel(from hero: HeroBriefing) -> String? {
        if hero.insights.contains(where: { $0.sourceKind == .sleep }) { return "Recovery" }
        if hero.actionLine.lowercased().contains("medication") { return "Health" }
        return "Mental Clarity"
    }

    private static func formatDurationMinutes(_ minutes: Int) -> String {
        minutes >= 120 ? "\(minutes / 60) h" : "\(max(1, minutes)) min"
    }
}
