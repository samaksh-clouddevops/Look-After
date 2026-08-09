import Foundation
import LookAfterCore
import LookAfterData

/// Builds orchestrator input from live app state.
public enum ProactiveActionsBuilder {
    public struct ShellSnapshot: Sendable {
        public var tasks: [LifeTask]
        public var timelineEvents: [LifeTimelineEvent]
        public var inboxItems: [InboxItem]
        public var memoryEntries: [MemoryEntry]
        public var contacts: [RelationshipContact]
        public var heroTask: LifeTask?
        public var focusSessionActive: Bool
        public var focusSessionElapsedMinutes: Int
        public var focusTaskTitle: String?
        public var capacityBand: ExecutiveCapacityBand?
        public var energyPercent: Int
        public var completedTodayCount: Int
        public var analyticsContext: CachedAIContextSummary?
        public var behaviorMemory: BehaviorMemorySnapshot
        public var calendarChange: CalendarChangeResult?
        public var bills: [BillItem]
        public var shoppingItems: [ShoppingItem]
        public var medications: [Medication]
        public var sleepHours: Double?
        public var captureGraphEdges: [CaptureGraphEdge]

        public init(
            tasks: [LifeTask],
            timelineEvents: [LifeTimelineEvent],
            inboxItems: [InboxItem] = [],
            memoryEntries: [MemoryEntry] = [],
            contacts: [RelationshipContact] = [],
            heroTask: LifeTask? = nil,
            focusSessionActive: Bool = false,
            focusSessionElapsedMinutes: Int = 0,
            focusTaskTitle: String? = nil,
            capacityBand: ExecutiveCapacityBand? = nil,
            energyPercent: Int = 55,
            completedTodayCount: Int = 0,
            analyticsContext: CachedAIContextSummary? = nil,
            behaviorMemory: BehaviorMemorySnapshot = .empty,
            calendarChange: CalendarChangeResult? = nil,
            bills: [BillItem] = [],
            shoppingItems: [ShoppingItem] = [],
            medications: [Medication] = [],
            sleepHours: Double? = nil,
            captureGraphEdges: [CaptureGraphEdge] = []
        ) {
            self.tasks = tasks
            self.timelineEvents = timelineEvents
            self.inboxItems = inboxItems
            self.memoryEntries = memoryEntries
            self.contacts = contacts
            self.heroTask = heroTask
            self.focusSessionActive = focusSessionActive
            self.focusSessionElapsedMinutes = focusSessionElapsedMinutes
            self.focusTaskTitle = focusTaskTitle
            self.capacityBand = capacityBand
            self.energyPercent = energyPercent
            self.completedTodayCount = completedTodayCount
            self.analyticsContext = analyticsContext
            self.behaviorMemory = behaviorMemory
            self.calendarChange = calendarChange
            self.bills = bills
            self.shoppingItems = shoppingItems
            self.medications = medications
            self.sleepHours = sleepHours
            self.captureGraphEdges = captureGraphEdges
        }
    }

    public static func analyze(
        snapshot: ShellSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = 8
    ) -> [ProactiveAction] {
        let input = ProactiveOrchestrator.Input(
            tasks: snapshot.tasks,
            referenceDate: now,
            now: now,
            energyPercent: snapshot.energyPercent,
            completedTodayCount: snapshot.completedTodayCount,
            calendar: calendar,
            timelineEvents: snapshot.timelineEvents,
            behaviorMemory: snapshot.behaviorMemory,
            analyticsContext: snapshot.analyticsContext,
            inboxItems: snapshot.inboxItems,
            memoryEntries: snapshot.memoryEntries,
            contacts: snapshot.contacts,
            heroTask: snapshot.heroTask,
            focusSessionActive: snapshot.focusSessionActive,
            focusSessionElapsedMinutes: snapshot.focusSessionElapsedMinutes,
            focusTaskTitle: snapshot.focusTaskTitle,
            capacityBand: snapshot.capacityBand,
            foregroundCount: AppForegroundTracker.foregroundCount(within: 20, now: now),
            calendarChange: snapshot.calendarChange
        )
        var actions = ProactiveOrchestrator.analyze(input, limit: limit + 4)

        if let batch = LifeAdminBatchCurator.curate(
            LifeAdminBatchCurator.Input(
                bills: snapshot.bills,
                shoppingItems: snapshot.shoppingItems,
                medications: snapshot.medications,
                contacts: snapshot.contacts,
                now: now
            )
        ) {
            actions.insert(LifeAdminBatchCurator.proactiveAction(from: batch), at: 0)
        }

        let deferralsToday = snapshot.behaviorMemory.deferralRecords.filter {
            guard let date = $0.lastDeferredAt else { return false }
            return calendar.isDateInToday(date)
        }.count
        if let badDay = BadDayDetector.evaluate(
            BadDayDetector.Input(
                capacityBand: snapshot.capacityBand,
                sleepHours: snapshot.sleepHours,
                deferralCountToday: deferralsToday,
                activeTaskCount: snapshot.tasks.filter(\.status.isActive).count
            )
        ) {
            actions.append(BadDayDetector.proactiveAction(from: badDay))
        }

        actions += CaptureClusterAnalyzer.analyze(
            inboxItems: snapshot.inboxItems,
            edges: snapshot.captureGraphEdges,
            now: now
        )

        actions = CrossDomainFusionAnalyzer.fuse(
            CrossDomainFusionAnalyzer.Input(
                actions: actions,
                bills: snapshot.bills,
                capacityBand: snapshot.capacityBand,
                sleepHours: snapshot.sleepHours,
                medications: snapshot.medications,
                now: now,
                calendar: calendar
            )
        )

        if let experiment = ExperimentFollowThroughDetector.evaluate(now: now, calendar: calendar) {
            actions.append(experiment)
        }

        if let weekShape = WeekShapeAnalyzer.evaluate(
            timelineEvents: snapshot.timelineEvents,
            deferralCount: snapshot.behaviorMemory.deferralRecords.filter { $0.deferralCount >= 3 }.count,
            tasks: snapshot.tasks,
            now: now,
            calendar: calendar
        ) {
            actions.append(weekShape)
        }

        if let weeklyDeferral = DeferralRecoveryWeeklyAgent.evaluate(
            deferralRecords: snapshot.behaviorMemory.deferralRecords,
            tasks: snapshot.tasks,
            now: now,
            calendar: calendar
        ) {
            actions.append(weeklyDeferral)
        }

        if let wake = WakeRecoveryDetector.evaluate(
            sleepHours: snapshot.sleepHours,
            timelineEvents: snapshot.timelineEvents,
            now: now,
            calendar: calendar
        ) {
            actions.append(WakeRecoveryDetector.proactiveAction(from: wake, now: now))
        }

        if let weekPrimer = WeekPrimerDetector.evaluate(tasks: snapshot.tasks, now: now, calendar: calendar) {
            actions.append(weekPrimer)
        }

        actions += PostCompletionAgent.evaluate(
            completedTodayCount: snapshot.completedTodayCount,
            nextTask: snapshot.tasks.first(where: { $0.status.isActive }),
            now: now
        )

        let bundleContext = ProactiveBundleBuilder.BuildContext(
            tasks: snapshot.tasks,
            inboxItems: snapshot.inboxItems,
            bills: snapshot.bills,
            now: now,
            calendar: calendar
        )
        actions = ProactiveBundleBuilder.enrich(actions, context: bundleContext)

        let ranked = ADHDProactiveRouting.rankFiltered(actions, now: now)
        return Array(dedupe(ranked).prefix(limit))
    }

    public static func loadBehaviorMemory() async -> BehaviorMemorySnapshot {
        let backend = FileBehaviorMemoryPersistenceBackend()
        let store = await BehaviorMemoryStore(backend: backend)
        let events = await store.fetchEvents()
        return BehaviorMemorySnapshotBuilder.build(from: events)
    }

    public static func loadCaptureGraphEdges() async -> [CaptureGraphEdge] {
        await CaptureGraphStore.shared.allEdges()
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
