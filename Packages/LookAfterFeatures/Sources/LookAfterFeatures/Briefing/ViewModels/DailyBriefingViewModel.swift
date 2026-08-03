import Foundation
import LookAfterCore
import LookAfterData
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
        isHealthConnected: false
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
    @Published public private(set) var mission = BriefingMissionData(tasks: [], completionPercent: 0)
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
    @Published public private(set) var lifeGaps: [LifeGap] = []
    @Published public private(set) var cycleData = BriefingCycleData.disabled
    @Published public var cardOrder: [BriefingCardKind] = BriefingCardKind.defaultOrder
    @Published public var hiddenCards: Set<BriefingCardKind> = []
    @Published public var pinnedCards: Set<BriefingCardKind> = []
    @Published public var layoutMode: BriefingLayoutMode = .detailed
    @Published public private(set) var isLoadingTrends = false

    private let healthRepo: HealthSummaryRepository
    private let analyticsService: BackgroundAnalyticsService?
    private var habitCompletionDates: [String: String] = [:]

    public var isPostWake: Bool { postWakeState.isPostWake }

    public func dismissPostWakeForToday() {
        PostWakeSessionStore.dismissForToday()
        postWakeState = .inactive
    }

    public init(
        healthRepo: HealthSummaryRepository? = nil,
        analyticsService: BackgroundAnalyticsService? = BackgroundAnalyticsService.shared
    ) {
        self.healthRepo = healthRepo ?? HealthSummaryRepository()
        self.analyticsService = analyticsService
        loadPreferences()
        loadHabitState()
    }

    public var visibleCards: [BriefingCardKind] {
        var ordered = cardOrder.filter { !hiddenCards.contains($0) }

        // Replace legacy metric trio with unified snapshot when snapshot is enabled.
        if !hiddenCards.contains(.healthSnapshot) {
            ordered.removeAll { BriefingCardKind.legacyMetricCards.contains($0) }
            if !ordered.contains(.healthSnapshot) {
                if let greetingIndex = ordered.firstIndex(of: .greeting) {
                    ordered.insert(.healthSnapshot, at: greetingIndex + 1)
                } else {
                    ordered.insert(.healthSnapshot, at: 0)
                }
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
        buildGreeting(userName: userName, flowSurface: flowSurface, heroBriefing: heroBriefing)
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
        let resolvedHealth = await resolveHealthSummary(
            brainSummary: brainVM.healthSummary,
            userId: userId
        )
        if brainVM.healthSummary == nil, let resolvedHealth {
            brainVM.healthSummary = resolvedHealth
        }

        buildGreeting(userName: userName, flowSurface: brainVM.flowSurface, heroBriefing: heroBriefing)
        buildExecutiveHero(heroBriefing: heroBriefing, brainDecision: brainDecision, brainVM: brainVM, tasksVM: tasksVM)
        buildDailySummary(snapshot: brainVM.cognitiveSnapshot, flowSurface: brainVM.flowSurface)
        buildSleep(health: resolvedHealth, snapshot: brainVM.cognitiveSnapshot, available: healthKitAvailable)
        buildEnergy(snapshot: brainVM.cognitiveSnapshot, flowSurface: brainVM.flowSurface)
        buildHealthSnapshot(
            snapshot: brainVM.cognitiveSnapshot,
            flowSurface: brainVM.flowSurface,
            healthKitAvailable: healthKitAvailable,
            healthSummary: resolvedHealth
        )
        buildMission(topTasks: brainVM.topTasks, completedToday: tasksVM.completedToday)
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
        buildLifeGaps(tasksVM: tasksVM)
        buildCycleData(healthSummary: resolvedHealth)
        refreshHabitCompletions()
        await loadWeeklyTrends(userId: userId, tasksVM: tasksVM)
    }

    /// Prefers brain cache, then loads directly from local storage (handles userId mismatches).
    private func resolveHealthSummary(brainSummary: HealthSummary?, userId: String) async -> HealthSummary? {
        if let brainSummary, healthHasVisibleMetrics(brainSummary) {
            return brainSummary
        }
        let canonicalId = FirebaseManager.shared.resolvedUserId
        let candidates = [canonicalId, userId].filter { !$0.isEmpty }
        for candidate in candidates {
            if let summary = try? await healthRepo.getLatest(for: candidate),
               healthHasVisibleMetrics(summary) {
                return summary
            }
        }
        return try? await healthRepo.getLatest(for: "")
    }

    public func toggleHabit(_ habit: BriefingHabit) {
        let today = Self.todayKey
        if habitCompletionDates[habit.id] == today {
            habitCompletionDates.removeValue(forKey: habit.id)
        } else {
            habitCompletionDates[habit.id] = today
        }
        persistHabitCompletions()
        refreshHabitCompletions()
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
        mission = BriefingMissionData(tasks: [], completionPercent: 0)
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
            isHealthConnected: false
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
        let left = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty || right.isEmpty { return false }
        return left == right || left.contains(right) || right.contains(left)
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
        let score = snapshot?.executiveFunctionScore ?? Int((flowSurface?.energyScore ?? 0.5) * 100)
        let energyPercent = Int((snapshot?.energyScore ?? flowSurface?.energyScore ?? 0.5) * 100)
        let recoveryPercent = Int((snapshot?.recoveryScore ?? 0.5) * 100)
        let sleepLabel = sleep.isAvailable ? sleep.totalHours.map { String(format: "%.1fh", $0) } : nil
        let focusWindow = resolveFocusWindow(flowSurface: flowSurface)

        let sleepQuality = sleepQualityLabel(score: score)
        let hasImportedHealth = sleep.isAvailable
            || (healthSummary.map(healthHasVisibleMetrics) ?? false)
            || UserDefaults.standard.object(forKey: "healthLastSyncDate") as? Date != nil
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
            isHealthConnected: healthKitAvailable && hasImportedHealth
        )
    }

    private func sleepQualityLabel(score: Int) -> String? {
        guard sleep.isAvailable else { return nil }
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

    private func resolveFocusWindow(flowSurface: FlowSurface?) -> String {
        if let interval = flowSurface?.flowWindow {
            return Self.formatInterval(interval)
        }
        let lifeProfile = UserLifeProfileStore.load()
        return FocusWindowFormatter.displayLabel(startHour: lifeProfile.peakStartHour, endHour: lifeProfile.peakEndHour)
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
        guard available,
              let health,
              (health.totalSleepMinutes ?? 0) > 0 else {
            sleep = BriefingSleepData(isAvailable: false)
            return
        }

        sleep = BriefingSleepData(
            totalHours: health.totalSleepMinutes.map { $0 / 60 },
            deepHours: health.deepSleepMinutes.map { $0 / 60 },
            remHours: health.remSleepMinutes.map { $0 / 60 },
            qualityPercent: health.sleepQualityScore.map { Int($0 * 100) },
            sleepDebtHours: snapshot?.sleepDebtHours ?? 0,
            isAvailable: true
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
    }

    private func buildMission(topTasks: [LifeTask], completedToday: [LifeTask]) {
        var items: [BriefingMissionTask] = completedToday.prefix(3).map {
            BriefingMissionTask(id: $0.id, title: $0.title, isCompleted: true, priority: $0.priority)
        }
        items += topTasks.prefix(6).map {
            BriefingMissionTask(id: $0.id, title: $0.title, isCompleted: false, priority: $0.priority)
        }

        let total = items.count
        let done = items.filter(\.isCompleted).count
        let percent = total > 0 ? Int((Double(done) / Double(total)) * 100) : 0

        mission = BriefingMissionData(tasks: items, completionPercent: percent)
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
        let overdue = tasksVM.tasks.filter(\.isOverdue).count
        let completed = tasksVM.completedToday.count
        let remaining = tasksVM.tasks.count
        let deepWork = tasksVM.completedToday.reduce(0) { $0 + $1.estimatedMinutes }
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
        if let data = UserDefaults.standard.data(forKey: StorageKey.habitCompletions),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            habitCompletionDates = decoded
        }
        refreshHabitCompletions()
    }

    private func persistHabitCompletions() {
        if let data = try? JSONEncoder().encode(habitCompletionDates) {
            UserDefaults.standard.set(data, forKey: StorageKey.habitCompletions)
        }
    }

    private func refreshHabitCompletions() {
        let today = Self.todayKey
        habits = BriefingHabit.defaults.map { habit in
            var copy = habit
            copy.isCompletedToday = habitCompletionDates[habit.id] == today
            return copy
        }
    }

    private func buildLifeGaps(tasksVM: TasksViewModel) {
        guard let model = LifeModelStore.load(), model.hasContent else {
            lifeGaps = []
            return
        }
        lifeGaps = LifeGapDetector.detect(
            model: model,
            completedTasks: tasksVM.completedToday,
            activeTasks: tasksVM.tasks
        )
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
