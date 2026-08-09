import Foundation

/// Fuses schedule, moment, pattern, and circuit-breaker detectors into ranked proactive actions.
public enum ProactiveOrchestrator {
    public struct Input: Sendable {
        public var tasks: [LifeTask]
        public var profile: UserLifeProfile
        public var lifeModel: LifeModel?
        public var referenceDate: Date
        public var now: Date
        public var energyPercent: Int
        public var completedTodayCount: Int
        public var calendar: Calendar
        public var timelineEvents: [LifeTimelineEvent]
        public var behaviorMemory: BehaviorMemorySnapshot
        public var analyticsContext: CachedAIContextSummary?
        public var adhdChallenge: ADHDFocusChallenge
        public var inboxItems: [InboxItem]
        public var memoryEntries: [MemoryEntry]
        public var contacts: [RelationshipContact]
        public var heroTask: LifeTask?
        public var focusSessionActive: Bool
        public var focusSessionElapsedMinutes: Int
        public var focusTaskTitle: String?
        public var capacityBand: ExecutiveCapacityBand?
        public var foregroundCount: Int
        public var calendarChange: CalendarChangeResult?

        public init(
            tasks: [LifeTask],
            profile: UserLifeProfile = UserLifeProfileStore.load(),
            lifeModel: LifeModel? = LifeModelStore.load(),
            referenceDate: Date = Date(),
            now: Date = Date(),
            energyPercent: Int = 55,
            completedTodayCount: Int = 0,
            calendar: Calendar = .current,
            timelineEvents: [LifeTimelineEvent] = [],
            behaviorMemory: BehaviorMemorySnapshot = .empty,
            analyticsContext: CachedAIContextSummary? = nil,
            adhdChallenge: ADHDFocusChallenge = ADHDFocusChallenge.load(),
            inboxItems: [InboxItem] = [],
            memoryEntries: [MemoryEntry] = [],
            contacts: [RelationshipContact] = [],
            heroTask: LifeTask? = nil,
            focusSessionActive: Bool = false,
            focusSessionElapsedMinutes: Int = 0,
            focusTaskTitle: String? = nil,
            capacityBand: ExecutiveCapacityBand? = nil,
            foregroundCount: Int = 0,
            calendarChange: CalendarChangeResult? = nil
        ) {
            self.tasks = tasks
            self.profile = profile
            self.lifeModel = lifeModel
            self.referenceDate = referenceDate
            self.now = now
            self.energyPercent = energyPercent
            self.completedTodayCount = completedTodayCount
            self.calendar = calendar
            self.timelineEvents = timelineEvents
            self.behaviorMemory = behaviorMemory
            self.analyticsContext = analyticsContext
            self.adhdChallenge = adhdChallenge
            self.inboxItems = inboxItems
            self.memoryEntries = memoryEntries
            self.contacts = contacts
            self.heroTask = heroTask
            self.focusSessionActive = focusSessionActive
            self.focusSessionElapsedMinutes = focusSessionElapsedMinutes
            self.focusTaskTitle = focusTaskTitle
            self.capacityBand = capacityBand
            self.foregroundCount = foregroundCount
            self.calendarChange = calendarChange
        }
    }

    public static func analyze(_ input: Input, limit: Int = 8) -> [ProactiveAction] {
        var actions: [ProactiveAction] = []

        let schedule = ScheduleProactiveAnalyzer.analyze(
            ScheduleProactiveAnalyzer.Input(
                tasks: input.tasks,
                profile: input.profile,
                lifeModel: input.lifeModel,
                referenceDate: input.referenceDate,
                now: input.now,
                energyPercent: input.energyPercent,
                completedTodayCount: input.completedTodayCount,
                calendar: input.calendar
            )
        ).map { ProactiveAction.from($0) }
        actions += schedule

        if let waiting = WaitingModeAnalyzer.analyze(tasks: input.tasks, now: input.now, calendar: input.calendar) {
            actions.append(WaitingModeAnalyzer.proactiveAction(from: waiting))
        }

        let transitions = TransitionShieldBuilder.transitions(
            timelineEvents: input.timelineEvents,
            tasks: input.tasks,
            now: input.now,
            calendar: input.calendar
        )
        actions += TransitionShieldBuilder.proactiveActions(from: transitions, now: input.now)

        let emailActions = actions.filter { $0.kind == .emailActionRequired }
        let relationshipActions = actions.filter { $0.kind == .relationshipDrift }
        actions += SocialDebtAgent.evaluate(emailActions: emailActions, relationshipActions: relationshipActions)

        actions += EndOfDayAgent.evaluate(
            tasks: input.tasks,
            profile: input.profile,
            lifeModel: input.lifeModel,
            referenceDate: input.referenceDate,
            now: input.now,
            calendar: input.calendar
        )

        if let change = input.calendarChange {
            actions.append(ProactiveAction(
                kind: .calendarChange,
                severity: .high,
                message: change.summaryLine,
                options: ["Preview replan", "Keep plan"],
                surface: .autoApplyPreview,
                relatedTaskIDs: change.newEvents.map(\.id)
            ))
        }

        if let bridge = InitiationBridgeDetector.analyze(
            heroTask: input.heroTask,
            behaviorMemory: input.behaviorMemory,
            foregroundCount: input.foregroundCount,
            focusSessionActive: input.focusSessionActive,
            now: input.now
        ) {
            actions.append(InitiationBridgeDetector.proactiveAction(from: bridge))
        }

        actions += PatternCoachAnalyzer.analyze(analytics: input.analyticsContext, now: input.now)
        actions += CaptureResurrectionAnalyzer.analyze(
            inboxItems: input.inboxItems,
            memoryEntries: input.memoryEntries,
            now: input.now
        )
        actions += CircuitBreakerAnalyzer.analyze(
            focusSessionActive: input.focusSessionActive,
            focusSessionElapsedMinutes: input.focusSessionElapsedMinutes,
            focusTaskTitle: input.focusTaskTitle,
            activeTaskCount: input.tasks.filter(\.status.isActive).count,
            behaviorMemory: input.behaviorMemory,
            capacityBand: input.capacityBand,
            now: input.now
        )

        for contact in input.contacts.filter(\.needsContact).prefix(1) {
            actions.append(ProactiveAction(
                kind: .relationshipDrift,
                severity: .medium,
                message: "You haven't talked to \(contact.name) in a while — 5-min check-in?",
                options: ["Schedule call", "Snooze", "Already did"],
                surface: .banner,
                metadata: ["contactID": contact.id, "contactName": contact.name]
            ))
        }

        let ranked = ADHDProactiveRouting.rankFiltered(actions, challenge: input.adhdChallenge, now: input.now)
        return dedupe(ranked).prefix(limit).map { $0 }
    }

    public static func topBannerAction(_ input: Input) -> ProactiveAction? {
        analyze(input).first { $0.surface == .banner || $0.surface == .autoApplyPreview }
    }

    private static func dedupe(_ actions: [ProactiveAction]) -> [ProactiveAction] {
        var seen = Set<String>()
        return actions.filter { action in
            let key = action.kind.rawValue + action.message
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
