import Foundation

import LookAfterCore
import LookAfterData
import LookAfterAI
import ExecutiveBrain

/// Builds Daily Briefing presentation state from brain, task, and health data.
@MainActor
public final class DailyBriefingViewModel: ObservableObject {

    private enum StorageKey {
        static let cardOrder = "briefingCardOrder"
        static let hiddenCards = "briefingHiddenCards"
        static let layoutMode = "briefingLayoutMode"
        static let pinnedCards = "briefingPinnedCards"
        static let habits = "briefingHabits"
        static let habitCompletions = "briefingHabitCompletions"
        static let lastDayAuditDayKey = "daySupervisor.lastAuditDayKey"
        static let dayAuditDismissedDayKey = "daySupervisor.dismissedQuestionsDayKey"
    }

    @Published public private(set) var greeting = BriefingGreeting(timeGreeting: "", userName: "", dateLine: "")
    @Published public private(set) var executiveHero: BriefingExecutiveHero?
    @Published public private(set) var healthSnapshot = BriefingHealthSnapshot(
        readinessLabel: UserFacingCopy.readinessLabel(score: 50),
        readinessScore: 50,
        readinessBand: UserFacingCopy.readinessBand(score: 50),
        energyPercent: 50,
        energyLevel: EnergyLevel.moderate.rawValue,
        recoveryLabel: UserFacingCopy.recoveryLabel(percent: 50),
        focusWindow: UserFacingCopy.noFocusWindowToday,
        isHealthConnected: false,
        hasOvernightHealthSignal: false
    )
    @Published public private(set) var highlightedCard: BriefingCardKind?
    @Published public private(set) var dailySummary = BriefingDailySummary(score: 0, narrative: "")
    @Published public private(set) var sleep = BriefingSleepData(isAvailable: false)
    @Published public private(set) var energy = BriefingEnergyData(
        currentEnergyPercent: 50,
        peakFocusWindow: "—",
        afternoonDipWindow: "—",
        recoveryPercent: 50,
        energyLevel: .moderate
    )
    @Published public private(set) var executiveCapacity: ExecutiveCapacityState = .moderate
    @Published public private(set) var mission = BriefingMissionData(tasks: [], completionPercent: 0, hiddenCompletedCount: 0)
    @Published public private(set) var calendar = BriefingCalendarData(isConnected: false)
    @Published public private(set) var health = BriefingHealthMetrics(isAvailable: false)
    @Published public private(set) var habits: [BriefingHabit] = BriefingHabit.defaults
    @Published public private(set) var aiRecommendation: String?
    @Published public private(set) var focusWindows: [BriefingFocusWindow] = []
    @Published public private(set) var progress = BriefingProgressData(
        completedCount: 0, remainingCount: 0, overdueCount: 0, deepWorkMinutes: 0, productivityScore: 0
    )
    @Published public private(set) var weeklyTrends = BriefingWeeklyTrends()
    @Published public private(set) var alerts: [BriefingAlert] = []
    @Published public private(set) var postWakeState: PostWakeDetector.Result = .inactive
    @Published public private(set) var dayBriefing: MorningDayBriefing?
    @Published public private(set) var dayHeroSummaryLines: [String] = []
    @Published public private(set) var isLoadingDayHeroSummary = false
    /// Chief-of-Staff narrative (max 4 sentences) + deterministic chips.
    @Published public private(set) var chiefNarrative: String = ""
    @Published public private(set) var chiefNarrativeSource: String = "deterministic"
    @Published public private(set) var chiefFromCache: Bool = false
    @Published public private(set) var snapshotChips: [BriefingSnapshotChip] = []
    @Published public private(set) var briefingPayload: BriefingPayload?
    @Published public private(set) var isLoadingChiefNarrative = false
    @Published public private(set) var lifeGaps: [LifeGap] = []
    @Published public private(set) var cycleData = BriefingCycleData.disabled
    @Published public private(set) var moduleInsights: [BriefingModuleInsight] = []
    @Published public private(set) var isLoadingModuleInsights = false
    /// Morning day-supervisor audit (sense / time / energy).
    @Published public private(set) var dayAudit: DayAuditResult?
    @Published public private(set) var isLoadingDayAudit = false
    @Published public var selectedDayAuditPullIDs: Set<String> = []
    @Published public var acceptedDayAuditFixIDs: Set<String> = []
    @Published public var dayAuditQuestionAnswers: [String: String] = [:]
    @Published public var skippedDayAuditQuestions = false
    @Published public private(set) var isStartingDay = false
    @Published public var cardOrder: [BriefingCardKind] = BriefingCardKind.defaultOrder
    @Published public var hiddenCards: Set<BriefingCardKind> = []
    @Published public var pinnedCards: Set<BriefingCardKind> = []
    @Published public var layoutMode: BriefingLayoutMode = .detailed
    @Published public private(set) var isLoadingTrends = false

    private let healthRepo: HealthSummaryRepository
    private let analyticsService: BackgroundAnalyticsService?
    private var habitCompletionDates: [String: String] = [:]
    private var orchestratedProactiveActions: [ProactiveAction] = []

    public var isPostWake: Bool { postWakeState.isPostWake }

    public func dismissPostWakeForToday() {
        PostWakeSessionStore.dismissForToday()
        postWakeState = .inactive
    }

    public func setProactiveActions(_ actions: [ProactiveAction]) {
        orchestratedProactiveActions = actions
    }

    public var proactiveActions: [ProactiveAction] {
        orchestratedProactiveActions
    }

    public init(
        healthRepo: HealthSummaryRepository? = nil,
        analyticsService: BackgroundAnalyticsService? = nil
    ) {
        self.healthRepo = healthRepo ?? HealthSummaryRepository()
        self.analyticsService = analyticsService ?? BackgroundAnalyticsService.shared
        loadPreferences()
        loadHabitState()
    }

    public var visibleCards: [BriefingCardKind] {
        var ordered = cardOrder.filter { !hiddenCards.contains($0) || pinnedCards.contains($0) }

        // Replace legacy metric trio with unified snapshot when snapshot is enabled.
        if !hiddenCards.contains(.healthSnapshot) {
            ordered.removeAll { BriefingCardKind.legacyMetricCards.contains($0) && !pinnedCards.contains($0) }
            if !ordered.contains(.healthSnapshot) {
                if let greetingIndex = ordered.firstIndex(of: .greeting) {
                    ordered.insert(.healthSnapshot, at: greetingIndex + 1)
                } else {
                    ordered.insert(.healthSnapshot, at: 0)
                }
            }
        }

        for kind in pinnedCards where !ordered.contains(kind) {
            if let greetingIndex = ordered.firstIndex(of: .greeting) {
                ordered.insert(kind, at: greetingIndex)
            } else {
                ordered.insert(kind, at: 0)
            }
        }

        if !hiddenCards.contains(.executiveHero), !ordered.contains(.executiveHero) {
            if let greetingIndex = ordered.firstIndex(of: .greeting) {
                ordered.insert(.executiveHero, at: greetingIndex + 1)
            } else {
                ordered.insert(.executiveHero, at: 0)
            }
        }

        let pinned = ordered.filter { pinnedCards.contains($0) }
        let unpinned = ordered.filter { !pinnedCards.contains($0) }
        return pinned + unpinned
    }

    public func cardEmphasis(for kind: BriefingCardKind) -> SurfaceEmphasis {
        if kind == .executiveHero { return .prominent }
        if kind == highlightedCard { return .standard }
        if kind == .healthSnapshot { return .subtle }
        if BriefingCardKind.legacyMetricCards.contains(kind) { return .subtle }
        return .subtle
    }

    public func updateGreeting(
        userName: String,
        flowSurface: FlowSurface? = nil,
        heroBriefing: HeroBriefing? = nil
    ) {
        greeting = BriefingProjector.projectGreeting(
            userName: userName,
            flowSurface: flowSurface,
            heroBriefing: heroBriefing
        )
    }

    public func applyProjectedSurface(_ surface: UnifiedBriefingSurface) {
        greeting = surface.greeting
        executiveHero = surface.executiveHero
    }

    public func refresh(
        brainVM: BrainViewModel,
        tasksVM: TasksViewModel,
        userId: String,
        userName: String,
        healthKitAvailable: Bool,
        heroBriefing: HeroBriefing? = nil,
        brainDecision: BrainDecision? = nil,
        lifeSnapshot: LifeContextSnapshot? = nil,
        lifeTimelineEvents: [LifeTimelineEvent] = [],
        tomorrowLifeTimelineEvents: [LifeTimelineEvent] = []
    ) async {
        let rawHealth = await resolveRawHealthSummary(
            brainRawSummary: brainVM.rawHealthSummary,
            brainSummary: brainVM.healthSummary,
            userId: userId
        )
        let resolvedHealth = HealthSummaryFreshness.forBriefingMetrics(from: rawHealth)

        updateGreeting(
            userName: userName,
            flowSurface: brainVM.flowSurface,
            heroBriefing: heroBriefing
        )

        buildDailySummary(snapshot: brainVM.cognitiveSnapshot, flowSurface: brainVM.flowSurface)
        buildSleep(health: rawHealth, snapshot: brainVM.cognitiveSnapshot, available: healthKitAvailable)
        buildEnergy(snapshot: brainVM.cognitiveSnapshot, flowSurface: brainVM.flowSurface)
        buildHealthSnapshot(
            snapshot: brainVM.cognitiveSnapshot,
            flowSurface: brainVM.flowSurface,
            healthKitAvailable: healthKitAvailable,
            healthSummary: resolvedHealth
        )
        buildMission(tasksVM: tasksVM, lifeTimelineEvents: lifeTimelineEvents)
        buildCalendar(flowSurface: brainVM.flowSurface)
        buildHealth(health: resolvedHealth, available: healthKitAvailable)
        buildAIRecommendation(brainVM: brainVM)
        buildFocusWindows(snapshot: brainVM.cognitiveSnapshot, flowSurface: brainVM.flowSurface)
        buildProgress(tasksVM: tasksVM, snapshot: brainVM.cognitiveSnapshot)
        buildAlerts(brainVM: brainVM, tasksVM: tasksVM)
        buildHighlightedCard(brainVM: brainVM, tasksVM: tasksVM)
        buildDayBriefing(
            healthSummary: resolvedHealth,
            executiveCapacity: executiveCapacity,
            lifeSnapshot: lifeSnapshot,
            lifeTimelineEvents: lifeTimelineEvents,
            tomorrowLifeTimelineEvents: tomorrowLifeTimelineEvents,
            tasksVM: tasksVM
        )
        refreshHabitCompletions()
        buildLifeGaps(tasksVM: tasksVM, userId: userId)
        buildCycleData(healthSummary: resolvedHealth)
        await refreshDayAudit(tasksVM: tasksVM)
        await buildDayHeroSummary(userName: userName, tasksVM: tasksVM, lifeTimelineEvents: lifeTimelineEvents)
        await buildChiefOfStaffNarrative(userName: userName, tasksVM: tasksVM)
        await buildModuleInsights(userName: userName, tasksVM: tasksVM)
        await loadWeeklyTrends(userId: userId, tasksVM: tasksVM)
    }

    /// Latest health with overnight fields intact — used for sleep display.
    private func resolveRawHealthSummary(
        brainRawSummary: HealthSummary?,
        brainSummary: HealthSummary?,
        userId: String
    ) async -> HealthSummary? {
        if let brainRawSummary, healthHasVisibleMetrics(brainRawSummary) {
            return ManualSleepLogStore.merged(with: brainRawSummary)
        }
        if let storeSummary = HealthStore.shared.latest, healthHasVisibleMetrics(storeSummary) {
            return storeSummary
        }
        if let refreshed = await HealthStore.shared.refresh(userId: userId), healthHasVisibleMetrics(refreshed) {
            return refreshed
        }

        let canonicalId = FirebaseManager.shared.resolvedUserId
        let candidates = [canonicalId, userId].filter { !$0.isEmpty }
        var resolved: HealthSummary?
        for candidate in candidates {
            if let summary = try? await healthRepo.getLatest(for: candidate),
               healthHasVisibleMetrics(summary) {
                resolved = summary
                break
            }
        }
        if resolved == nil {
            resolved = try? await healthRepo.getLatest(for: "")
        }
        if let resolved {
            return ManualSleepLogStore.merged(with: resolved)
        }

        if let brainSummary, healthHasVisibleMetrics(brainSummary) {
            return ManualSleepLogStore.merged(with: brainSummary)
        }
        return ManualSleepLogStore.merged(with: nil)
    }

    public func toggleHabit(_ habit: BriefingHabit, tasksVM: TasksViewModel? = nil, userId: String = "") {
        let today = Self.todayKey
        _ = HabitCompletionStore.toggle(habitId: habit.id, todayKey: today)
        habitCompletionDates = HabitCompletionStore.latestCompletionDates()
        refreshHabitCompletions()
        if let tasksVM {
            refreshLifeGaps(tasksVM: tasksVM, userId: userId.isEmpty ? FirebaseManager.shared.resolvedUserId : userId)
        }
        NotificationCenter.default.post(
            name: .analyticsDataDidChange,
            object: nil,
            userInfo: ["reason": AnalyticsDataChangeReason.habitChanged.rawValue]
        )
    }

    public func setCardHidden(_ kind: BriefingCardKind, hidden: Bool) {
        if hidden {
            hiddenCards.insert(kind)
        } else {
            hiddenCards.remove(kind)
        }
        persistPreferences()
    }

    public func togglePin(_ kind: BriefingCardKind) {
        if pinnedCards.contains(kind) {
            pinnedCards.remove(kind)
        } else {
            pinnedCards.insert(kind)
            hiddenCards.remove(kind)
        }
        persistPreferences()
    }

    public func moveCard(from source: IndexSet, to destination: Int) {
        cardOrder.move(fromOffsets: source, toOffset: destination)
        persistPreferences()
    }

    public func setLayoutMode(_ mode: BriefingLayoutMode) {
        layoutMode = mode
        persistPreferences()
    }

    public func resetCardLayout() {
        cardOrder = BriefingCardKind.defaultOrder
        hiddenCards = BriefingCardKind.legacyMetricCards
        pinnedCards = []
        layoutMode = .detailed
        persistPreferences()
    }

    public func updateExecutiveCapacity(_ state: ExecutiveCapacityState) {
        executiveCapacity = state
    }

    /// Resets briefing presentation state after a developer data wipe.
    public func resetAfterDeveloperWipe() {
        resetCardLayout()
        habitCompletionDates = [:]
        persistHabitCompletions()
        refreshHabitCompletions()
        executiveCapacity = .moderate
        executiveHero = nil
        aiRecommendation = nil
        focusWindows = []
        alerts = []
        postWakeState = .inactive
        dayBriefing = nil
        dailySummary = BriefingDailySummary(score: 0, narrative: "")
        sleep = BriefingSleepData(isAvailable: false)
        energy = BriefingEnergyData(
            currentEnergyPercent: 50,
            peakFocusWindow: "—",
            afternoonDipWindow: "—",
            recoveryPercent: 50,
            energyLevel: .moderate
        )
        mission = BriefingMissionData(tasks: [], completionPercent: 0, hiddenCompletedCount: 0)
        calendar = BriefingCalendarData(isConnected: false)
        health = BriefingHealthMetrics(isAvailable: false)
        progress = BriefingProgressData(
            completedCount: 0, remainingCount: 0, overdueCount: 0, deepWorkMinutes: 0, productivityScore: 0
        )
        healthSnapshot = BriefingHealthSnapshot(
            readinessLabel: UserFacingCopy.readinessLabel(score: 50),
            readinessScore: 50,
            readinessBand: UserFacingCopy.readinessBand(score: 50),
            energyPercent: 50,
            energyLevel: EnergyLevel.moderate.rawValue,
            recoveryLabel: UserFacingCopy.recoveryLabel(percent: 50),
            focusWindow: UserFacingCopy.noFocusWindowToday,
            isHealthConnected: false,
            hasOvernightHealthSignal: false
        )
    }

    // MARK: - Builders

    private func buildGreeting(userName: String, flowSurface: FlowSurface?, heroBriefing: HeroBriefing?) {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "Good morning"
        case 12..<17: timeGreeting = "Good afternoon"
        case 17..<21: timeGreeting = "Good evening"
        default: timeGreeting = "Good night"
        }

        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let displayName = name.isEmpty ? "" : name

        if let heroGreeting = heroBriefing?.greeting, !heroGreeting.isEmpty {
            applyGreetingLine(heroGreeting, displayName: displayName)
            return
        }

        if let flowGreeting = flowSurface?.greeting, !flowGreeting.isEmpty {
            let hasName = !name.isEmpty && flowGreeting.localizedCaseInsensitiveContains(name)
            if hasName {
                greeting = BriefingGreeting(
                    timeGreeting: flowGreeting.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                    userName: "",
                    dateLine: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                )
            } else {
                let cleanFlowGreeting = flowGreeting.trimmingCharacters(in: CharacterSet(charactersIn: ".!,"))
                greeting = BriefingGreeting(
                    timeGreeting: cleanFlowGreeting,
                    userName: displayName,
                    dateLine: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                )
            }
        } else {
            greeting = BriefingGreeting(
                timeGreeting: timeGreeting,
                userName: displayName,
                dateLine: Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            )
        }
    }

    private func buildExecutiveHero(
        heroBriefing: HeroBriefing?,
        brainDecision: BrainDecision?,
        brainVM: BrainViewModel,
        tasksVM: TasksViewModel
    ) {
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
                fallback: brainVM.recommendation
            )
            let ignoreConsequence = hero.whyNowReasons.dropFirst().first.map { UserFacingCopy.sanitize($0) }
            let duration = hero.durationEstimate.pointMinutes > 0
                ? Self.formatDurationMinutes(hero.durationEstimate.pointMinutes)
                : nil
            let button = UserFacingCopy.sanitize(hero.buttonLabel)

            executiveHero = BriefingExecutiveHero(
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
            return
        }

        if let decision = brainDecision {
            let rendered = IntentRenderer.hero(from: decision.intent, whyNow: decision.whyNow)
            executiveHero = BriefingExecutiveHero(
                greeting: greetingDisplayLine(),
                narrative: UserFacingCopy.sanitize(decision.supportingLine),
                actionLine: UserFacingCopy.sanitize(decision.headline),
                whyLine: decision.whyNow.first.map { UserFacingCopy.sanitize($0) },
                buttonLabel: UserFacingCopy.sanitize(rendered.primaryButton),
                durationLabel: rendered.durationLabel.isEmpty ? nil : rendered.durationLabel
            )
            return
        }

        if let surface = brainVM.flowSurface {
            let heroTask = surface.heroTask ?? brainVM.topTasks.first
            let actionLine = heroTask.map { HumanLanguage.outcomeHeadline(task: $0) } ?? "Pick up where you left off"
            let narrative = surface.briefingLines.prefix(2).joined(separator: " ")
            let why = surface.prediction?.reasoning ?? surface.coachMoment?.message

            executiveHero = BriefingExecutiveHero(
                greeting: greetingDisplayLine(),
                narrative: UserFacingCopy.sanitize(narrative.isEmpty ? (brainVM.recommendation) : narrative),
                actionLine: UserFacingCopy.sanitize(actionLine),
                whyLine: why.map { UserFacingCopy.sanitize($0) },
                buttonLabel: UserFacingCopy.sanitize(surface.prediction?.buttonLabel ?? actionLine),
                durationLabel: surface.prediction.map {
                    UserFacingCopy.actionDurationSubtitle(minutes: $0.suggestedDurationMinutes)
                }
            )
            return
        }

        executiveHero = nil
    }

    private func composeNarrative(
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
           !isDuplicateCopy(supportingLine, actionLine) {
            parts.append(supportingLine)
        }
        if parts.isEmpty {
            let sanitized = UserFacingCopy.sanitize(fallback)
            if !sanitized.isEmpty, !UserFacingCopy.isGenericMotivation(sanitized),
               !isDuplicateCopy(sanitized, actionLine) {
                parts.append(sanitized)
            }
        }
        return parts.joined(separator: " ")
    }

    private func distinctWhyLine(supporting: String, primaryWhy: String?, headline: String) -> String? {
        if !supporting.isEmpty, !isDuplicateCopy(supporting, headline) {
            return supporting
        }
        if let primaryWhy, !primaryWhy.isEmpty, !isDuplicateCopy(primaryWhy, headline) {
            return primaryWhy
        }
        return nil
    }

    private func isDuplicateCopy(_ a: String, _ b: String) -> Bool {
        UserFacingCopy.isDuplicateCopy(a, b)
    }

    private func applyGreetingLine(_ source: String, displayName: String) {
        let trimmed = source.trimmingCharacters(in: CharacterSet(charactersIn: ".!,"))
        let dateLine = Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if !displayName.isEmpty, trimmed.localizedCaseInsensitiveContains(displayName) {
            greeting = BriefingGreeting(timeGreeting: trimmed, userName: "", dateLine: dateLine)
        } else {
            greeting = BriefingGreeting(timeGreeting: trimmed, userName: displayName, dateLine: dateLine)
        }
    }

    private func inferImpactLabel(from hero: HeroBriefing) -> String? {
        if hero.confidenceLevel == .high { return "High Impact" }
        if hero.confidenceLevel == .medium { return "Medium Impact" }
        return nil
    }

    private func inferClarityLabel(from hero: HeroBriefing) -> String? {
        if hero.insights.contains(where: { $0.sourceKind == .sleep }) { return "Recovery" }
        if hero.actionLine.lowercased().contains("medication") { return "Health" }
        return "Mental Clarity"
    }

    private static func formatDurationMinutes(_ minutes: Int) -> String {
        minutes >= 120 ? "\(minutes / 60) h" : "\(max(1, minutes)) min"
    }

    private func greetingDisplayLine() -> String {
        if greeting.userName.isEmpty {
            return greeting.timeGreeting
        }
        return "\(greeting.timeGreeting), \(greeting.userName)"
    }

    private func buildHealthSnapshot(
        snapshot: CognitiveSnapshot?,
        flowSurface: FlowSurface?,
        healthKitAvailable: Bool,
        healthSummary: HealthSummary?
    ) {
        let hasOvernight = healthSummary.map { HealthSummaryFreshness.hasLastNightSleep($0) } ?? false
        let liveEnergyPercent = Int((snapshot?.energyScore ?? flowSurface?.energyScore ?? 0.5) * 100)
        let liveRecoveryPercent = Int((snapshot?.recoveryScore ?? 0.5) * 100)
        let score = snapshot?.executiveFunctionScore ?? liveEnergyPercent
        let energyPercent = liveEnergyPercent
        let recoveryPercent = liveRecoveryPercent
        let sleepLabel = sleep.isAvailable ? sleep.totalHours.map { String(format: "%.1fh", $0) } : nil
        let focusWindow = resolveFocusWindow(flowSurface: flowSurface, hasOvernightHealth: hasOvernight)

        let sleepQuality = sleepQualityLabel(score: score, hasOvernightSleep: sleep.isLastNightSleep)
        let hasImportedHealth = sleep.isAvailable
            || (healthSummary.map(healthHasVisibleMetrics) ?? false)
        healthSnapshot = BriefingHealthSnapshot(
            readinessLabel: UserFacingCopy.readinessLabel(score: score),
            readinessScore: score,
            readinessBand: UserFacingCopy.readinessBand(score: score),
            sleepHours: sleepLabel,
            sleepQuality: sleepQuality,
            energyPercent: energyPercent,
            energyLevel: (snapshot?.energy ?? energy.energyLevel).rawValue,
            recoveryLabel: UserFacingCopy.recoveryLabel(percent: recoveryPercent),
            recoveryPercent: recoveryPercent,
            focusWindow: focusWindow,
            isHealthConnected: healthKitAvailable && hasImportedHealth,
            hasOvernightHealthSignal: hasOvernight
        )
    }

    private func sleepQualityLabel(score: Int, hasOvernightSleep: Bool) -> String? {
        guard sleep.isAvailable else { return nil }
        if !hasOvernightSleep { return "Last recorded" }
        if let pct = sleep.qualityPercent {
            switch pct {
            case 80...: return "Good"
            case 60..<80: return "Fair"
            default: return "Low"
            }
        }
        return UserFacingCopy.readinessBand(score: score)
    }

    private func buildHighlightedCard(brainVM: BrainViewModel, tasksVM: TasksViewModel) {
        if (brainVM.cognitiveSnapshot?.sleepDebtHours ?? 0) >= 1.5 {
            highlightedCard = .healthSnapshot
            return
        }
        if calendar.nextEventTitle != nil {
            highlightedCard = .calendar
            return
        }
        if !alerts.isEmpty {
            highlightedCard = .alerts
            return
        }
        if tasksVM.tasks.contains(where: \.isOverdue) {
            highlightedCard = .mission
            return
        }
        highlightedCard = .aiCoach
    }

    private func resolveFocusWindow(flowSurface: FlowSurface?, hasOvernightHealth: Bool) -> String {
        if let interval = flowSurface?.flowWindow {
            return Self.formatInterval(interval)
        }

        let lifeProfile = UserLifeProfileStore.load()
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let peakLabel = FocusWindowFormatter.displayLabel(
            startHour: lifeProfile.peakStartHour,
            endHour: lifeProfile.peakEndHour
        )

        if hour >= lifeProfile.peakStartHour && hour < lifeProfile.peakEndHour {
            return "Now · \(peakLabel)"
        }

        if hour < lifeProfile.peakStartHour {
            let prefix = hasOvernightHealth ? "Up next" : "Typical"
            return "\(prefix) · \(peakLabel)"
        }

        return hasOvernightHealth ? peakLabel : "Typical · \(peakLabel)"
    }

    private func buildDailySummary(snapshot: CognitiveSnapshot?, flowSurface: FlowSurface?) {
        let score = snapshot?.executiveFunctionScore ?? Int((flowSurface?.energyScore ?? 0.5) * 100)
        var narrative = snapshot?.contextNotes ?? ""

        if narrative.isEmpty, let lines = flowSurface?.briefingLines, !lines.isEmpty {
            narrative = lines.joined(separator: " ")
        }
        if narrative.isEmpty {
            narrative = Self.defaultNarrative(score: score, snapshot: snapshot)
        }

        dailySummary = BriefingDailySummary(
            score: score,
            scoreLabel: UserFacingCopy.readinessLabel(score: score),
            scoreBand: UserFacingCopy.readinessBand(score: score),
            narrative: UserFacingCopy.sanitize(narrative)
        )
    }

    private func buildSleep(health: HealthSummary?, snapshot: CognitiveSnapshot?, available: Bool) {
        if let entry = ManualSleepLogStore.entry() {
            let targetHours = IdealSleepPlanner.defaultTargetSleepHours()
            let hours = entry.rating.estimatedMinutes(targetSleepHours: targetHours) / 60
            sleep = BriefingSleepData(
                totalHours: hours,
                qualityPercent: Int(entry.rating.qualityScore * 100),
                sleepDebtHours: snapshot?.sleepDebtHours ?? 0,
                isAvailable: true,
                isLastNightSleep: true
            )
            return
        }

        guard available,
              let health,
              (health.totalSleepMinutes ?? 0) > 0 else {
            sleep = BriefingSleepData(isAvailable: false)
            return
        }

        let isLastNight = HealthSummaryFreshness.hasLastNightSleep(health)
        sleep = BriefingSleepData(
            totalHours: health.totalSleepMinutes.map { $0 / 60 },
            deepHours: health.deepSleepMinutes.map { $0 / 60 },
            remHours: health.remSleepMinutes.map { $0 / 60 },
            qualityPercent: isLastNight ? health.sleepQualityScore.map { Int($0 * 100) } : nil,
            sleepDebtHours: snapshot?.sleepDebtHours ?? 0,
            isAvailable: true,
            isLastNightSleep: isLastNight
        )
    }

    private func buildEnergy(snapshot: CognitiveSnapshot?, flowSurface: FlowSurface?) {
        let lifeProfile = UserLifeProfileStore.load()
        let peakStartHour = lifeProfile.peakStartHour
        let peakEndHour = lifeProfile.peakEndHour

        var peakWindow = FocusWindowFormatter.displayLabel(startHour: peakStartHour, endHour: peakEndHour)
        if let interval = flowSurface?.flowWindow {
            peakWindow = Self.formatInterval(interval)
        }

        let energyPercent = Int((snapshot?.energyScore ?? flowSurface?.energyScore ?? 0.5) * 100)
        let recoveryPercent = Int((snapshot?.recoveryScore ?? 0.5) * 100)

        energy = BriefingEnergyData(
            currentEnergyPercent: energyPercent,
            peakFocusWindow: peakWindow,
            afternoonDipWindow: lifeProfile.afternoonDipWindowLabel,
            recoveryPercent: recoveryPercent,
            energyLevel: snapshot?.energy ?? .moderate
        )
    }

    private func buildDayBriefing(
        healthSummary: HealthSummary?,
        executiveCapacity: ExecutiveCapacityState,
        lifeSnapshot: LifeContextSnapshot?,
        lifeTimelineEvents: [LifeTimelineEvent],
        tomorrowLifeTimelineEvents: [LifeTimelineEvent],
        tasksVM: TasksViewModel
    ) {
        let postWake = PostWakeDetector.evaluate(
            PostWakeDetector.Input(
                wakeTime: healthSummary?.wakeTime,
                lastBackgroundAt: PostWakeSessionStore.lastBackgroundAt(),
                dismissedOnDay: PostWakeSessionStore.dismissedOnDay()
            )
        )
        postWakeState = postWake

        dayBriefing = MorningDayBriefingBuilder.build(
            .init(
                postWake: postWake,
                healthSummary: healthSummary,
                sleep: sleep,
                executiveCapacity: executiveCapacity,
                lifeSnapshot: lifeSnapshot,
                lifeTimelineEvents: lifeTimelineEvents,
                tomorrowTimelineEvents: tomorrowLifeTimelineEvents,
                tasks: tasksVM.tasks,
                completedToday: tasksVM.completedToday,
                calendarData: calendar,
                focusWindowLabel: healthSnapshot.focusWindow
            )
        )
    }

    private func buildMission(tasksVM: TasksViewModel, lifeTimelineEvents: [LifeTimelineEvent] = []) {
        let allTasks = tasksVM.schedulingContext
        let now = Date()
        let calendar = Calendar.current

        let scheduledCompleted: [LifeTask]
        let scheduledActive: [LifeTask]

        if !lifeTimelineEvents.isEmpty {
            let completedIds = Set(
                lifeTimelineEvents
                    .filter { $0.isCompleted && $0.id.hasPrefix("task-") }
                    .compactMap { String($0.id.dropFirst(5)) }
            )
            let activeIds = Set(
                lifeTimelineEvents
                    .filter { !$0.isCompleted && $0.id.hasPrefix("task-") }
                    .compactMap { String($0.id.dropFirst(5)) }
            )
            scheduledCompleted = tasksVM.completedToday.filter { completedIds.contains($0.id) }
            scheduledActive = tasksVM.tasks.filter { activeIds.contains($0.id) }
        } else {
            scheduledCompleted = LifeTimelinePresenter.completedTasksScheduledForToday(
                from: tasksVM.completedToday,
                allTasks: allTasks,
                now: now,
                calendar: calendar
            )
            scheduledActive = tasksVM.reconciledScheduledTasksForToday(now: now, calendar: calendar)
        }

        let dedupedCompleted = dedupeMissionTasks(scheduledCompleted)
        let dedupedActive = dedupeMissionTasks(scheduledActive)
        let completedIds = Set(dedupedCompleted.map(\.id))
        let pending = dedupedActive.filter { !completedIds.contains($0.id) }

        let completedCap = 5
        let visibleCompleted = Array(dedupedCompleted.prefix(completedCap))
        let hiddenCompleted = max(0, dedupedCompleted.count - visibleCompleted.count)

        var items: [BriefingMissionTask] = visibleCompleted.map { missionTask(from: $0, isCompleted: true) }
        items += pending.prefix(6).map { missionTask(from: $0, isCompleted: false) }

        let totalScheduled = Set(dedupedCompleted.map(\.id) + dedupedActive.map(\.id)).count
        let done = dedupedCompleted.count
        let percent = totalScheduled > 0 ? Int((Double(done) / Double(totalScheduled)) * 100) : 0

        mission = BriefingMissionData(
            tasks: items,
            completionPercent: percent,
            hiddenCompletedCount: hiddenCompleted
        )
    }

    private func dedupeMissionTasks(_ tasks: [LifeTask]) -> [LifeTask] {
        var seen = Set<String>()
        var result: [LifeTask] = []
        for task in tasks {
            let key = TaskScheduleQuery.seriesKey(for: task)
            guard seen.insert(key).inserted else { continue }
            result.append(task)
        }
        return result
    }

    private func missionTask(from task: LifeTask, isCompleted: Bool) -> BriefingMissionTask {
        let day = Calendar.current.startOfDay(for: Date())
        let scheduleLabel: String?
        switch TaskScheduleInterval.displaySchedule(for: task, on: day) {
        case .unslottedFlexible:
            scheduleLabel = "Flexible today"
        case .window(_, _, let rangeLabel):
            scheduleLabel = "Start \(rangeLabel.components(separatedBy: " – ").first ?? rangeLabel)"
        case .noSchedule:
            scheduleLabel = nil
        }
        return BriefingMissionTask(
            id: task.id,
            title: task.title,
            isCompleted: isCompleted,
            priority: task.priority,
            scheduleLabel: scheduleLabel
        )
    }

    private func buildCalendar(flowSurface: FlowSurface?) {
        guard let event = flowSurface?.nextCalendarEvent else {
            calendar = BriefingCalendarData(isConnected: true)
            return
        }

        let duration = max(Int(event.endDate.timeIntervalSince(event.startDate) / 60), 0)
        calendar = BriefingCalendarData(
            nextEventTitle: event.title,
            minutesUntilStart: event.minutesUntilStart,
            durationMinutes: duration,
            isConnected: true
        )
    }

    private func buildHealth(health: HealthSummary?, available: Bool) {
        guard available, let health, healthHasVisibleMetrics(health) else {
            self.health = BriefingHealthMetrics(isAvailable: false)
            return
        }

        let movePercent: Int? = {
            guard let steps = health.stepCount else { return nil }
            return min(Int((Double(steps) / 10_000) * 100), 100)
        }()

        self.health = BriefingHealthMetrics(
            steps: health.stepCount,
            moveRingPercent: movePercent,
            exerciseMinutes: health.exerciseMinutes,
            standHours: health.standHours,
            restingHR: health.restingHeartRate.map { Int($0) },
            hrv: health.hrvAverage.map { Int($0) },
            isAvailable: true
        )
    }

    private func healthHasVisibleMetrics(_ health: HealthSummary) -> Bool {
        if (health.totalSleepMinutes ?? 0) > 0 { return true }
        if (health.stepCount ?? 0) > 0 { return true }
        if health.restingHeartRate != nil || health.averageHeartRate != nil { return true }
        if health.hrvAverage != nil { return true }
        if (health.workoutCount ?? 0) > 0 { return true }
        return false
    }

    private func buildAIRecommendation(brainVM: BrainViewModel) {
        if let coach = brainVM.flowSurface?.coachMoment, !coach.message.isEmpty {
            aiRecommendation = UserFacingCopy.sanitize(coach.message)
            return
        }

        if let prediction = brainVM.flowSurface?.prediction, !prediction.reasoning.isEmpty {
            aiRecommendation = UserFacingCopy.sanitize(prediction.reasoning)
            return
        }

        let lines = brainVM.recommendation
            .components(separatedBy: .newlines)
            .map { UserFacingCopy.sanitize($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty && !UserFacingCopy.isGenericMotivation($0) }

        aiRecommendation = lines.first
    }

    private func buildFocusWindows(snapshot: CognitiveSnapshot?, flowSurface: FlowSurface?) {
        let lifeProfile = UserLifeProfileStore.load()
        let peakStartHour = lifeProfile.peakStartHour
        let peakEndHour = lifeProfile.peakEndHour
        let workoutStart = min(max(lifeProfile.workEndHour - 1, peakEndHour + 1), 22)
        let workoutEnd = min(workoutStart + 2, 23)
        let recoveryStartMinutes = lifeProfile.workEndHour * 60 + lifeProfile.workEndMinute + 60
        let recoveryEndMinutes = recoveryStartMinutes + 90
        let recoveryStartHour = min(recoveryStartMinutes / 60, 23)
        let recoveryStartMinute = recoveryStartMinutes % 60
        let recoveryEndHour = min(recoveryEndMinutes / 60, 23)
        let recoveryEndMinute = recoveryEndMinutes % 60
        let recoveryLabel = "\(Self.formatHour(recoveryStartHour, minute: recoveryStartMinute)) – \(Self.formatHour(recoveryEndHour, minute: recoveryEndMinute))"

        var windows: [BriefingFocusWindow] = [
            BriefingFocusWindow(
                id: "open",
                label: "\(Self.formatHour(peakStartHour)) – \(Self.formatHour(peakEndHour))",
                timeRange: UserFacingCopy.defaultWindowDetail,
                icon: "clock"
            ),
            BriefingFocusWindow(
                id: "workout",
                label: "\(Self.formatHour(workoutStart)) – \(Self.formatHour(workoutEnd))",
                timeRange: UserFacingCopy.workoutWindowDetail,
                icon: "figure.run"
            ),
            BriefingFocusWindow(
                id: "creative",
                label: "\(Self.formatHour(max(peakStartHour - 1, 7))) – \(Self.formatHour(peakStartHour + 1))",
                timeRange: UserFacingCopy.creativeWindowDetail,
                icon: "lightbulb.fill"
            ),
            BriefingFocusWindow(
                id: "recovery",
                label: recoveryLabel,
                timeRange: UserFacingCopy.recoveryWindowDetail,
                icon: "moon.stars.fill"
            ),
        ]

        if let interval = flowSurface?.flowWindow {
            windows[0] = BriefingFocusWindow(
                id: "open",
                label: Self.formatInterval(interval),
                timeRange: UserFacingCopy.defaultWindowDetail,
                icon: "clock"
            )
        }

        if (snapshot?.energyScore ?? 0.5) < 0.4 {
            windows[0] = BriefingFocusWindow(
                id: "open",
                label: windows[0].label,
                timeRange: UserFacingCopy.lowEnergyWindowDetail,
                icon: "clock"
            )
        }

        focusWindows = windows
    }

    private func buildProgress(tasksVM: TasksViewModel, snapshot: CognitiveSnapshot?) {
        let allTasks = tasksVM.tasks + tasksVM.completedToday + tasksVM.recurrenceTemplates
        let now = Date()
        let calendar = Calendar.current

        let scheduledCompleted = LifeTimelinePresenter.completedTasksScheduledForToday(
            from: tasksVM.completedToday,
            allTasks: allTasks,
            now: now,
            calendar: calendar
        )
        let dedupedCompleted = dedupeMissionTasks(scheduledCompleted)
        let scheduledActive = tasksVM.reconciledScheduledTasksForToday(now: now, calendar: calendar)
        let dedupedActive = dedupeMissionTasks(scheduledActive)

        let overdue = dedupedActive.filter(\.isOverdue).count
        let completed = dedupedCompleted.count
        let remaining = dedupedActive.filter { task in
            !dedupedCompleted.contains(where: { $0.id == task.id })
        }.count
        let deepWork = dedupedCompleted.reduce(0) { $0 + $1.estimatedMinutes }
        let productivity = snapshot?.executiveFunctionScore ?? min(completed * 15, 100)

        progress = BriefingProgressData(
            completedCount: completed,
            remainingCount: remaining,
            overdueCount: overdue,
            deepWorkMinutes: deepWork,
            productivityScore: productivity
        )
    }

    private func buildAlerts(brainVM: BrainViewModel, tasksVM: TasksViewModel) {
        var result: [BriefingAlert] = []

        if let snapshot = brainVM.cognitiveSnapshot, snapshot.sleepDebtHours >= 2 {
            result.append(BriefingAlert(
                id: "sleep-debt",
                title: "Sleep debt increasing",
                message: String(format: "You're running %.1f hours behind on sleep.", snapshot.sleepDebtHours),
                icon: "moon.zzz.fill",
                severity: .warning
            ))
        }

        let overdue = tasksVM.tasks.filter(\.isOverdue)
        if overdue.count >= 3 {
            result.append(BriefingAlert(
                id: "overdue-tasks",
                title: "High workload detected",
                message: "You have \(overdue.count) overdue tasks. Consider postponing lower priority work.",
                icon: "exclamationmark.triangle.fill",
                severity: .urgent
            ))
        } else         if !overdue.isEmpty {
            result.append(BriefingAlert(
                id: "overdue-tasks",
                title: "Overdue tasks",
                message: "\(overdue.count) task\(overdue.count == 1 ? "" : "s") need attention.",
                icon: "clock.badge.exclamationmark",
                severity: .warning
            ))
        }

        // Medication alerts come from ExecutiveBrain (schedule-bound, never invented timing).
        // Do not add generic "take medication" alerts here.

        if let hrv = brainVM.healthSummary?.hrvAverage, hrv < 30 {
            result.append(BriefingAlert(
                id: "hrv-low",
                title: "Recovery signal",
                message: "HRV is lower than usual. Prioritize lighter tasks this afternoon.",
                icon: "waveform.path.ecg",
                severity: .warning
            ))
        }

        for notice in brainVM.flowSurface?.rescheduledTasks.prefix(1) ?? [] {
            result.append(BriefingAlert(
                id: "reschedule-\(notice.id)",
                title: "Schedule update",
                message: notice.explanation,
                icon: "calendar.badge.clock",
                severity: .info
            ))
        }

        alerts = result
    }

    private func loadWeeklyTrends(userId: String, tasksVM: TasksViewModel) async {
        if let analyticsService,
           let cached = analyticsService.cachedWeeklyReport(userId: userId) {
            weeklyTrends = cached.briefingWeeklyTrends
            isLoadingTrends = false
            analyticsService.scheduleRefresh(userId: userId, trigger: .briefingOpened)
            return
        }

        isLoadingTrends = true
        defer { isLoadingTrends = false }

        if let analyticsService {
            await analyticsService.refreshIfNeeded(userId: userId, trigger: .briefingOpened)
            if let report = analyticsService.cachedWeeklyReport(userId: userId) {
                weeklyTrends = report.briefingWeeklyTrends
                return
            }
        }

        // Fallback when cache is unavailable (tests / first launch without service).
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else { return }

        do {
            let summaries = try await healthRepo.getForDateRange(from: weekAgo, to: Date(), userId: userId)
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"

            var sleepPoints: [BriefingTrendPoint] = []
            var energyPoints: [BriefingTrendPoint] = []
            var stepPoints: [BriefingTrendPoint] = []

            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekAgo) else { continue }
                let label = dayFormatter.string(from: day)
                let summary = summaries.first { calendar.isDate($0.date, inSameDayAs: day) }

                sleepPoints.append(BriefingTrendPoint(
                    id: "sleep-\(offset)",
                    label: label,
                    value: (summary?.totalSleepMinutes ?? 0) / 60
                ))
                energyPoints.append(BriefingTrendPoint(
                    id: "energy-\(offset)",
                    label: label,
                    value: (summary?.sleepQualityScore ?? 0.5) * 100
                ))
                stepPoints.append(BriefingTrendPoint(
                    id: "steps-\(offset)",
                    label: label,
                    value: Double(summary?.stepCount ?? 0)
                ))
            }

            let completionRate = tasksVM.completedToday.isEmpty ? 0 : Double(tasksVM.completedToday.count)
            var taskPoints: [BriefingTrendPoint] = []
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekAgo) else { continue }
                let label = dayFormatter.string(from: day)
                let value = calendar.isDateInToday(day) ? completionRate * 10 : Double(offset + 1) * 5
                taskPoints.append(BriefingTrendPoint(id: "tasks-\(offset)", label: label, value: value))
            }

            weeklyTrends = BriefingWeeklyTrends(
                sleep: sleepPoints,
                energy: energyPoints,
                steps: stepPoints,
                taskCompletion: taskPoints
            )
        } catch {
            weeklyTrends = BriefingWeeklyTrends()
        }
    }

    /// Applies cached weekly trends when background analytics finish refreshing.
    public func applyCachedWeeklyTrends(userId: String) {
        guard let report = analyticsService?.cachedWeeklyReport(userId: userId) else { return }
        weeklyTrends = report.briefingWeeklyTrends
        isLoadingTrends = false
    }

    // MARK: - Preferences

    private func loadPreferences() {
        if let raw = UserDefaults.standard.stringArray(forKey: StorageKey.cardOrder) {
            let kinds = raw.compactMap(BriefingCardKind.init(rawValue:))
            if !kinds.isEmpty { cardOrder = kinds }
        }
        if let raw = UserDefaults.standard.stringArray(forKey: StorageKey.hiddenCards) {
            hiddenCards = Set(raw.compactMap(BriefingCardKind.init(rawValue:)))
        }
        if let raw = UserDefaults.standard.stringArray(forKey: StorageKey.pinnedCards) {
            pinnedCards = Set(raw.compactMap(BriefingCardKind.init(rawValue:)))
        }
        if let raw = UserDefaults.standard.string(forKey: StorageKey.layoutMode),
           let mode = BriefingLayoutMode(rawValue: raw) {
            layoutMode = mode
        }
    }

    private func persistPreferences() {
        UserDefaults.standard.set(cardOrder.map(\.rawValue), forKey: StorageKey.cardOrder)
        UserDefaults.standard.set(hiddenCards.map(\.rawValue), forKey: StorageKey.hiddenCards)
        UserDefaults.standard.set(pinnedCards.map(\.rawValue), forKey: StorageKey.pinnedCards)
        UserDefaults.standard.set(layoutMode.rawValue, forKey: StorageKey.layoutMode)
    }

    private func loadHabitState() {
        habitCompletionDates = HabitCompletionStore.latestCompletionDates()
        refreshHabitCompletions()
    }

    private func persistHabitCompletions() {
        let history = habitCompletionDates.reduce(into: [String: [String]]()) { partial, entry in
            partial[entry.key] = [entry.value]
        }
        HabitCompletionStore.save(history)
    }

    private func refreshHabitCompletions() {
        let today = Self.todayKey
        habits = BriefingHabit.defaults.map { habit in
            var copy = habit
            copy.isCompletedToday = habitCompletionDates[habit.id] == today
            return copy
        }
    }

    /// Recomputes life-gap cards from the latest task state — call after task completion.
    public func refreshLifeGaps(tasksVM: TasksViewModel, userId: String) {
        refreshHabitCompletions()
        buildLifeGaps(tasksVM: tasksVM, userId: userId)
    }

    /// Lightweight progress + mission refresh after task completion — avoids a full briefing reload.
    public func refreshTaskProgress(
        brainVM: BrainViewModel,
        tasksVM: TasksViewModel,
        healthKitAvailable: Bool,
        lifeTimelineEvents: [LifeTimelineEvent] = []
    ) {
        let metricsHealth = HealthSummaryFreshness.forBriefingMetrics(
            from: brainVM.rawHealthSummary ?? brainVM.healthSummary
        )
        buildProgress(tasksVM: tasksVM, snapshot: brainVM.cognitiveSnapshot)
        buildMission(tasksVM: tasksVM, lifeTimelineEvents: lifeTimelineEvents)
        buildEnergy(snapshot: brainVM.cognitiveSnapshot, flowSurface: brainVM.flowSurface)
        buildHealthSnapshot(
            snapshot: brainVM.cognitiveSnapshot,
            flowSurface: brainVM.flowSurface,
            healthKitAvailable: healthKitAvailable,
            healthSummary: metricsHealth
        )
    }

    private func buildLifeGaps(tasksVM: TasksViewModel, userId: String) {
        guard let model = LifeModelStore.load(), model.hasContent else {
            lifeGaps = []
            return
        }

        let canonicalId = FirebaseManager.shared.resolvedUserId
        var candidateIds = Set<String>()
        if !canonicalId.isEmpty { candidateIds.insert(canonicalId) }
        if !userId.isEmpty { candidateIds.insert(userId) }
        candidateIds.insert("")

        var tasksByID: [String: LifeTask] = [:]
        for candidate in candidateIds {
            for task in tasksVM.localAllTasks(userId: candidate) {
                tasksByID[task.id] = task
            }
        }
        // In-memory lists win — they carry optimistic completions before disk/cache catches up.
        for task in tasksVM.tasks + tasksVM.recurrenceTemplates + tasksVM.completedToday {
            tasksByID[task.id] = task
        }

        let habitsToday = Set(habits.filter(\.isCompletedToday).map(\.id))
        lifeGaps = LifeGapDetector.detect(
            model: model,
            allTasks: Array(tasksByID.values),
            habitsCompletedToday: habitsToday
        )
    }

    private func buildDayHeroSummary(
        userName: String,
        tasksVM: TasksViewModel,
        lifeTimelineEvents: [LifeTimelineEvent]
    ) async {
        isLoadingDayHeroSummary = true
        defer { isLoadingDayHeroSummary = false }

        let input = BriefingDayHeroSummaryGenerator.Input(
            userName: userName,
            dayBriefing: dayBriefing,
            mission: mission,
            progress: progress,
            executiveCapacity: executiveCapacity,
            energy: energy,
            calendar: calendar,
            sleep: sleep,
            tasks: tasksVM.tasks,
            completedToday: tasksVM.completedToday,
            lifeTimelineEvents: lifeTimelineEvents
        )
        dayHeroSummaryLines = await BriefingDayHeroSummaryGenerator.generate(input)
        // Prefer supervisor findings over vibe copy when the day has material faults.
        if let audit = dayAudit, audit.hasMaterialFindings {
            let auditLines = audit.summaryLines
                .map { UserFacingCopy.humanizeBriefingLine($0) }
                .filter { !$0.isEmpty }
            if !auditLines.isEmpty {
                dayHeroSummaryLines = Array(auditLines.prefix(BriefingDayHeroSummaryGenerator.maxHeroLines))
            }
        }
    }

    /// Runs the deterministic day supervisor audit (parked + yesterday + capacity).
    public func refreshDayAudit(tasksVM: TasksViewModel, now: Date = Date(), calendar: Calendar = .current) async {
        isLoadingDayAudit = true
        defer { isLoadingDayAudit = false }

        let dayKey = Self.dayKey(for: now, calendar: calendar)
        let parked = ParkedTaskQueueStore.shared.candidatesForReintegration(limit: 8)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        let yesterdayIncomplete: [LifeTask] = {
            guard let yesterday else { return [] }
            return tasksVM.localAllTasks(userId: FirebaseManager.shared.resolvedUserId).filter { task in
                guard task.status.isActive, let date = task.scheduledDate else { return false }
                return calendar.isDate(date, inSameDayAs: yesterday)
            }
        }()

        let result = DayAuditService.run(
            DayAuditService.Input(
                tasks: tasksVM.schedulingContext,
                yesterdayIncomplete: yesterdayIncomplete,
                parkedCandidates: parked,
                energyPercent: energy.currentEnergyPercent,
                capacityBandLabel: executiveCapacity.band.displayLabel,
                referenceDate: now,
                now: now,
                calendar: calendar
            )
        )
        dayAudit = result

        // Reset interactive state once per calendar day.
        let lastKey = UserDefaults.standard.string(forKey: StorageKey.lastDayAuditDayKey)
        if lastKey != dayKey {
            selectedDayAuditPullIDs = []
            acceptedDayAuditFixIDs = Set(result.proposedFixes.map(\.id))
            dayAuditQuestionAnswers = [:]
            skippedDayAuditQuestions = UserDefaults.standard.string(forKey: StorageKey.dayAuditDismissedDayKey) == dayKey
            UserDefaults.standard.set(dayKey, forKey: StorageKey.lastDayAuditDayKey)
        }

        // Re-apply audit lines onto hero when material.
        if result.hasMaterialFindings {
            let auditLines = result.summaryLines
                .map { UserFacingCopy.humanizeBriefingLine($0) }
                .filter { !$0.isEmpty }
            if !auditLines.isEmpty {
                dayHeroSummaryLines = Array(auditLines.prefix(BriefingDayHeroSummaryGenerator.maxHeroLines))
            }
        }
    }

    public var dayAuditQuestionsResolved: Bool {
        guard let audit = dayAudit, audit.hasBlockingQuestions else { return true }
        if skippedDayAuditQuestions { return true }
        return audit.clarifyingQuestions.allSatisfy { dayAuditQuestionAnswers[$0.id] != nil }
    }

    public func answerDayAuditQuestion(id: String, option: String) {
        dayAuditQuestionAnswers[id] = option
    }

    public func skipDayAuditQuestions(now: Date = Date(), calendar: Calendar = .current) {
        skippedDayAuditQuestions = true
        UserDefaults.standard.set(Self.dayKey(for: now, calendar: calendar), forKey: StorageKey.dayAuditDismissedDayKey)
    }

    public func toggleDayAuditPull(_ id: String) {
        if selectedDayAuditPullIDs.contains(id) {
            selectedDayAuditPullIDs.remove(id)
        } else {
            selectedDayAuditPullIDs.insert(id)
        }
    }

    public func toggleDayAuditFix(_ id: String) {
        if acceptedDayAuditFixIDs.contains(id) {
            acceptedDayAuditFixIDs.remove(id)
        } else {
            acceptedDayAuditFixIDs.insert(id)
        }
    }

    /// Returns true when navigation to Today should proceed.
    @discardableResult
    public func startMyDay(
        tasksVM: TasksViewModel,
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        isStartingDay = true
        defer { isStartingDay = false }

        if !userId.isEmpty {
            await tasksVM.reconcileTodaySchedule(userId: userId, date: now, calendar: calendar)
        }
        await refreshDayAudit(tasksVM: tasksVM, now: now, calendar: calendar)

        guard dayAuditQuestionsResolved else { return false }

        let audit = dayAudit
        let fixes = (audit?.proposedFixes ?? []).filter { acceptedDayAuditFixIDs.contains($0.id) }
        let pulls = (audit?.possiblePulls ?? []).filter { selectedDayAuditPullIDs.contains($0.id) }

        if !fixes.isEmpty || !pulls.isEmpty {
            await DayAuditApplier.apply(
                acceptedFixes: fixes,
                selectedPulls: pulls,
                tasksVM: tasksVM,
                userId: userId,
                now: now,
                calendar: calendar
            )
        }
        return true
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    /// Payload-to-Prompt Chief of Staff narrative — cached, sanitized, non-blocking.
    private func buildChiefOfStaffNarrative(userName: String, tasksVM: TasksViewModel) async {
        isLoadingChiefNarrative = true
        defer { isLoadingChiefNarrative = false }

        let parked = ParkedTaskQueueStore.shared
        _ = parked.applyFluidDecay()
        let recovery = ParkedTaskRecoveryService.shared
        let decayedCount = parked.snapshot().decayedEntries.count

        // Macro cascade actions only (CascadeDistiller → overnight log).
        let distilledActions = CascadeActionLog.shared.systemActions()
        let distilledMutations = CascadeDistiller.mutationFacts(from: distilledActions)

        let payload = BriefingPayloadCompiler.compile(
            .init(
                energy: energy.energyLevel,
                energyPercent: energy.currentEnergyPercent,
                sleepHours: sleep.totalHours,
                capacityBandLabel: executiveCapacity.band.displayLabel,
                tasks: tasksVM.tasks + tasksVM.completedToday,
                cascadeDecisions: [],
                parkedRecoverableCount: parked.candidatesForReintegration(limit: 50).count,
                somedayDecayCount: decayedCount,
                telemetryLearnings: recovery.briefingNotes().map { BriefingPIISanitizer.scrub($0) },
                nextEventTitle: calendar.nextEventTitle,
                minutesUntilNextEvent: calendar.minutesUntilStart,
                resurrectedTaskIDs: recovery.resurrectedIDs()
            )
        )
        // Prefer distilled mutation facts when overnight cascade ran.
        var payloadWithMutations = payload
        if !distilledMutations.isEmpty {
            payloadWithMutations.mutations = distilledMutations
            // Tallies from distilled codes when statuses not yet on tasks.
            payloadWithMutations.supersededTaskCount = max(
                payload.supersededTaskCount,
                distilledMutations.filter { $0.code == "superseded" }.count
            )
            payloadWithMutations.expiredTaskCount = max(
                payload.expiredTaskCount,
                distilledMutations.filter { $0.code == "expired" }.count
            )
            let recovery = payload.hasRecoveryBlockToday
                || distilledActions.contains { $0.lowercased().contains("sabotage") }
            payloadWithMutations.hasRecoveryBlockToday = recovery
            payloadWithMutations.structureFingerprint = BriefingPayload.fingerprint(for: payloadWithMutations)
        }
        let finalPayload = distilledMutations.isEmpty ? payload : payloadWithMutations
        briefingPayload = finalPayload
        snapshotChips = finalPayload.snapshotChips()

        // Instant fallback while AI may be in-flight (never looks broken).
        if let audit = dayAudit, audit.hasMaterialFindings {
            chiefNarrative = audit.summaryLines.joined(separator: " ")
            chiefNarrativeSource = "day_audit"
        } else if chiefNarrative.isEmpty {
            chiefNarrative = finalPayload.deterministicNarrative(userName: userName)
            chiefNarrativeSource = "deterministic"
        }

        // Supervisor findings already answered the morning — skip vibe LLM.
        if dayAudit?.hasMaterialFindings == true {
            return
        }

        let hasKey = GLMService.shared.hasConfiguredAPIKey

        // AIRouter: distilled systemActions → immutable system prompt (no raw cascade spam).
        let routerPayload = BriefingRouterPayload(from: finalPayload)
        let compiled = BriefingPromptGenerator.compile(routerPayload)

        let glmComplete: (@Sendable (String, String) async throws -> String)?
        if hasKey {
            let userPrompt = compiled.user
            let systemPrompt = compiled.system
            glmComplete = { _, _ in
                try await GLMService.shared.complete(
                    prompt: userPrompt,
                    systemPrompt: systemPrompt,
                    tier: .economy
                )
            }
        } else {
            glmComplete = nil
        }
        let result = await ChiefOfStaffBriefingSynthesizer.synthesize(
            payload: finalPayload,
            userName: userName,
            forceRefresh: false,
            glmComplete: glmComplete
        )
        chiefNarrative = result.narrative
        chiefNarrativeSource = result.source
        chiefFromCache = result.fromCache
        snapshotChips = result.chips
    }

    private func buildModuleInsights(userName: String, tasksVM: TasksViewModel) async {
        isLoadingModuleInsights = true
        defer { isLoadingModuleInsights = false }

        let proactive: [ScheduleProactiveSuggestion] = {
            if !orchestratedProactiveActions.isEmpty {
                return orchestratedProactiveActions.compactMap(\.asScheduleSuggestion)
            }
            return ScheduleProactiveAnalyzer.analyze(
                ScheduleProactiveAnalyzer.Input(
                    tasks: tasksVM.schedulingContext,
                    now: Date(),
                    energyPercent: energy.currentEnergyPercent,
                    completedTodayCount: progress.completedCount
                )
            )
        }()

        let input = BriefingModuleInsightsBuilder.Input(
            userName: userName,
            progress: progress,
            mission: mission,
            sleep: sleep,
            energy: energy,
            executiveCapacity: executiveCapacity,
            habits: habits,
            calendar: calendar,
            lifeGaps: lifeGaps,
            proactiveSuggestions: proactive,
            cycleData: cycleData,
            alerts: alerts,
            aiRecommendation: aiRecommendation
        )
        var insights = BriefingModuleInsightsBuilder.buildDeterministic(input)
        insights = await BriefingModuleInsightsBuilder.supplementWithAI(existing: insights, input: input)
        moduleInsights = insights
    }

    private func buildCycleData(healthSummary: HealthSummary?) {
        guard CycleFeatureGate.isEligible else {
            cycleData = .disabled
            return
        }
        let preferences = CyclePreferencesStore.load()
        guard preferences.isEnabled else {
            cycleData = .disabled
            return
        }

        let logs = CycleLogStore.load()
        let snapshot = CycleEngine.snapshot(CycleEngine.Input(preferences: preferences, logs: logs))
        let sleepHours = healthSummary.flatMap { summary in
            summary.totalSleepMinutes.map { Double($0) / 60.0 }
        }
        let insights = CycleInsightBuilder.build(
            snapshot: snapshot,
            logs: logs,
            sleepHours: sleepHours,
            hrv: healthSummary?.hrvAverage.map { Int($0) }
        )
        cycleData = BriefingCycleData(snapshot: snapshot, topInsight: insights.first)
    }

    // MARK: - Helpers

    private static var todayKey: String {
        ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())).prefix(10).description
    }

    private static func formatHour(_ hour: Int, minute: Int = 0) -> String {
        let normalizedHour = ((hour % 24) + 24) % 24
        let normalizedMinute = min(max(minute, 0), 59)
        let suffix = normalizedHour >= 12 ? "PM" : "AM"
        let displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12
        if normalizedMinute == 0 {
            return "\(displayHour):00 \(suffix)"
        }
        return String(format: "%d:%02d %@", displayHour, normalizedMinute, suffix)
    }

    private static func formatInterval(_ interval: DateInterval) -> String {
        FocusWindowFormatter.displayLabel(for: interval)
    }

    private static func defaultNarrative(score: Int, snapshot: CognitiveSnapshot?) -> String {
        if score >= 80 {
            return "You slept well and your energy is above average. Tackle your most important task while you have the bandwidth."
        }
        if score >= 60 {
            return "You're in a solid zone today. Use your open window for the task that matters most."
        }
        if (snapshot?.sleepDebtHours ?? 0) > 1 {
            return "Sleep debt is building. Keep tasks lighter and protect recovery time tonight."
        }
        return "Start with one meaningful task. Momentum matters more than perfection today."
    }
}
