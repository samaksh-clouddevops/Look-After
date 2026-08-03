import SwiftUI
import LifeOSCore
import LifeOSFeatures
import LifeOSHealth
import LifeOSData

/// Briefing — full-height immersive hero; context unfolds in scroll chapters.
struct DailyBriefingView: View {

    @EnvironmentObject private var shell: AppShellState
    @ObservedObject var briefingVM: DailyBriefingViewModel
    @ObservedObject var brainVM: BrainViewModel
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var healthSync: HealthSyncService
    @ObservedObject private var analytics = BackgroundAnalyticsService.shared

    let userId: String
    @AppStorage("userName") private var userName = ""
    @AppStorage("enableHealth") private var enableHealth = true

    var onOpenToday: () -> Void
    var onOpenTasks: () -> Void
    var onOpenCoach: () -> Void
    var onOpenDailyPlan: () -> Void
    var onOpenSettings: () -> Void
    var onCapture: () -> Void
    var onStartTask: (LifeTask) -> Void
    var onReplanDay: (() -> Void)?

    @State private var showCustomization = false
    @State private var showHealthConnectSheet = false
    @State private var showCycleLog = false
    @State private var showCycleDashboard = false
    @State private var scrollOffset: CGFloat = 0

    private var showsScrollHint: Bool {
        scrollOffset < 40
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                PremiumBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        firstViewport
                        scrollChapters
                    }
                    .background(
                        GeometryReader { contentGeo in
                            Color.clear.preference(
                                key: BriefingScrollOffsetKey.self,
                                value: -contentGeo.frame(in: .named("briefingScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "briefingScroll")
                .onPreferenceChange(BriefingScrollOffsetKey.self) { scrollOffset = $0 }
                .refreshable {
                    await reload()
                }

                if showsScrollHint {
                    BriefingScrollAffordance()
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.25), value: showsScrollHint)
        }
        .task(id: refreshToken) {
            await reload()
        }
        .onChange(of: analytics.lastRefreshAt) { _, _ in
            briefingVM.applyCachedWeeklyTrends(userId: userId)
        }
        .sheet(isPresented: $showCustomization) {
            DailyBriefingCustomizationView(briefingVM: briefingVM)
        }
        .sheet(isPresented: $showHealthConnectSheet) {
            HealthConnectSheet(healthSync: healthSync, userId: userId)
                .environmentObject(shell)
        }
        .sheet(isPresented: $showCycleLog) {
            CycleQuickLogSheet(viewModel: CycleDashboardViewModel())
        }
        .sheet(isPresented: $showCycleDashboard) {
            NavigationStack {
                CycleDashboardView()
            }
        }
        .onChange(of: healthSync.syncPhase) { _, phase in
            guard phase == .complete else { return }
            Task { await reload() }
        }
    }

    // MARK: - First viewport

    private var firstViewport: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXL) {
            headerBar
            BriefingGreetingHeader(greeting: briefingVM.greeting)

            Group {
                if let overview = briefingVM.dayBriefing {
                    BriefingDayOverviewCard(
                        briefing: overview,
                        isMorningStyle: briefingVM.isPostWake,
                        onOpenTimeline: onOpenToday,
                        onOpenTasks: onOpenTasks,
                        onCapture: onCapture
                    )
                }

                if let hero = briefingVM.executiveHero, hero.isActionableTask {
                    BriefingNextActionStrip(
                        hero: hero,
                        task: resolveHeroTask(hero),
                        onStart: {
                            if let task = resolveHeroTask(hero) {
                                onStartTask(task)
                            } else {
                                onOpenToday()
                            }
                        }
                    )
                }

                LifeGapsCard(gaps: briefingVM.lifeGaps, onOpenTimeline: onOpenToday)
            }

            BriefingSnapshotStrip(snapshot: briefingVM.healthSnapshot)
        }
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .padding(.top, DesignSystem.spacingSM)
        .padding(.bottom, DesignSystem.spacingXL)
    }

    // MARK: - Scroll chapters (below the fold)

    private var scrollChapters: some View {
        VStack(spacing: DesignSystem.BriefingViewport.chapterSpacing) {
            if hasSnapshotDetailsChapter {
                BriefingChapterSection(
                    title: "Details",
                    subtitle: snapshotChapterSubtitle,
                    icon: "chart.bar.doc.horizontal"
                ) {
                    snapshotChapterContent
                }
            }

            if hasHealthChapter {
                BriefingChapterSection(
                    title: "Health",
                    subtitle: healthChapterSubtitle,
                    icon: "heart.fill"
                ) {
                    healthChapterContent
                }
            }

            if hasScheduleChapter {
                BriefingChapterSection(
                    title: "Schedule",
                    subtitle: scheduleChapterSubtitle,
                    icon: "calendar"
                ) {
                    scheduleChapterContent
                }
            }

            if hasRecommendationsChapter {
                BriefingChapterSection(
                    title: "More for today",
                    subtitle: recommendationsChapterSubtitle,
                    icon: "sparkles"
                ) {
                    recommendationsChapterContent
                }
            }

            Color.clear.frame(height: DesignSystem.spacingXXL)
        }
    }

    // MARK: - Chapter content

    @ViewBuilder
    private var snapshotChapterContent: some View {
        VStack(spacing: DesignSystem.spacingLG) {
            if isVisible(.progress) {
                BriefingProgressCard(progress: briefingVM.progress, compact: true)
            }
            if isVisible(.mission) {
                BriefingMissionCard(
                    mission: briefingVM.mission,
                    compact: true,
                    onAddTask: onOpenTasks,
                    onReplanDay: onReplanDay
                )
            }
            if isVisible(.healthSnapshot), briefingVM.healthSnapshot.isHealthConnected {
                BriefingHealthSnapshotCard(snapshot: briefingVM.healthSnapshot)
            }
        }
    }

    @ViewBuilder
    private var healthChapterContent: some View {
        VStack(spacing: DesignSystem.spacingLG) {
            if isVisible(.sleep) {
                BriefingSleepCard(sleep: briefingVM.sleep, compact: true, onConnectHealth: connectHealth)
            }
            if isVisible(.energy) {
                ExecutiveCapacityCard(capacity: briefingVM.executiveCapacity, compact: true)
            }
            if isVisible(.health) {
                BriefingHealthCard(health: briefingVM.health, compact: true, onConnectHealth: connectHealth)
            }
            if isVisible(.cycle), briefingVM.cycleData.isVisible {
                BriefingCycleCard(
                    cycleData: briefingVM.cycleData,
                    compact: true,
                    onLog: { showCycleLog = true },
                    onOpenDashboard: { showCycleDashboard = true }
                )
            }
            if isVisible(.dailySummary) {
                BriefingDailySummaryCard(summary: briefingVM.dailySummary, compact: true)
            }
        }
    }

    @ViewBuilder
    private var scheduleChapterContent: some View {
        VStack(spacing: DesignSystem.spacingLG) {
            if isVisible(.calendar) {
                BriefingCalendarCard(
                    calendar: briefingVM.calendar,
                    compact: true,
                    onConnectCalendar: onOpenDailyPlan
                )
            }
            if isVisible(.focusPrediction) {
                BriefingFocusPredictionCard(windows: briefingVM.focusWindows, compact: true)
            }
        }
    }

    @ViewBuilder
    private var recommendationsChapterContent: some View {
        VStack(spacing: DesignSystem.spacingLG) {
            if isVisible(.aiCoach) {
                BriefingAICoachCard(
                    recommendation: briefingVM.aiRecommendation,
                    compact: true,
                    onOpenCoach: onOpenCoach
                )
            }
            if isVisible(.alerts) {
                BriefingAlertsCard(alerts: briefingVM.alerts)
            }
            if isVisible(.habits) {
                BriefingHabitsCard(habits: briefingVM.habits, compact: true) { habit in
                    briefingVM.toggleHabit(habit)
                }
            }
            if isVisible(.weeklyTrends) {
                BriefingWeeklyTrendsCard(
                    trends: briefingVM.weeklyTrends,
                    isLoading: briefingVM.isLoadingTrends
                )
            }
        }
    }

    // MARK: - Chapter visibility

    private func isVisible(_ kind: BriefingCardKind) -> Bool {
        briefingVM.visibleCards.contains(kind)
    }

    private var hasSnapshotDetailsChapter: Bool {
        isVisible(.progress) || isVisible(.mission)
            || (isVisible(.healthSnapshot) && briefingVM.healthSnapshot.isHealthConnected)
    }

    private var hasSnapshotChapter: Bool {
        hasSnapshotDetailsChapter
    }

    private var hasHealthChapter: Bool {
        isVisible(.sleep) || isVisible(.energy) || isVisible(.health) || isVisible(.dailySummary)
            || (isVisible(.cycle) && briefingVM.cycleData.isVisible)
    }

    private var hasScheduleChapter: Bool {
        isVisible(.calendar) || isVisible(.focusPrediction)
    }

    private var hasRecommendationsChapter: Bool {
        isVisible(.aiCoach) || isVisible(.alerts) || isVisible(.habits) || isVisible(.weeklyTrends)
    }

    // MARK: - Copy helpers

    private func resolveHeroTask(_ hero: BriefingExecutiveHero) -> LifeTask? {
        if let id = hero.actionTaskID {
            return tasksVM.tasks.first { $0.id == id && $0.status.isActive }
        }
        return tasksVM.tasks.first(where: \.status.isActive)
    }

    private var snapshotPreviewHint: String {
        let readiness = briefingVM.healthSnapshot.readinessLabel
        let pct = briefingVM.mission.completionPercent
        if pct > 0 {
            return "\(readiness) · \(pct)% of today done"
        }
        return readiness
    }

    private var snapshotChapterSubtitle: String {
        "\(briefingVM.healthSnapshot.readinessLabel) · \(briefingVM.mission.completionPercent)% complete"
    }

    private var healthChapterSubtitle: String {
        var parts: [String] = []
        if briefingVM.sleep.isAvailable, let hours = briefingVM.sleep.totalHours {
            parts.append(String(format: "%.1fh sleep", hours))
        }
        parts.append(briefingVM.executiveCapacity.band.displayLabel)
        return parts.joined(separator: " · ")
    }

    private var scheduleChapterSubtitle: String {
        if let title = briefingVM.calendar.nextEventTitle {
            return title
        }
        return briefingVM.energy.peakFocusWindow
    }

    private var recommendationsChapterSubtitle: String {
        if let rec = briefingVM.aiRecommendation, !rec.isEmpty {
            return CalmHeroContentBuilder.firstSentence(rec)
        }
        if !briefingVM.alerts.isEmpty {
            return "\(briefingVM.alerts.count) item\(briefingVM.alerts.count == 1 ? "" : "s") need attention"
        }
        return "Suggestions and habits"
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: DesignSystem.spacingSM) {
            Circle()
                .fill(DesignSystem.accentPrimary)
                .frame(width: 8, height: 8)

            Text(briefingVM.greeting.dateLine)
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textMuted)
                .lineLimit(1)

            Spacer()

            if brainVM.isLoading {
                ProgressView()
                    .tint(DesignSystem.textMuted)
                    .scaleEffect(0.8)
            }

            Button(action: { showCustomization = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DesignSystem.backgroundElevated))
            }
            .accessibilityLabel("Customize briefing")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DesignSystem.backgroundElevated))
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Data

    private var refreshToken: String {
        [
            userId,
            String(brainVM.cognitiveSnapshot?.executiveFunctionScore ?? 0),
            String(tasksVM.tasks.count),
            String(tasksVM.completedToday.count),
            String(brainVM.healthSummary?.totalSleepMinutes ?? 0),
            String(brainVM.healthSummary?.stepCount ?? 0),
            healthSync.lastSyncDate?.timeIntervalSince1970.description ?? "0",
            brainVM.flowSurface?.generatedAt.description ?? "",
            shell.contextOrchestrator.briefing?.generatedAt.description ?? "",
        ].joined(separator: "-")
    }

    private func connectHealth() {
        guard enableHealth else { return }
        showHealthConnectSheet = true
    }

    private func reload() async {
        let resolvedId = FirebaseManager.shared.resolvedUserId.isEmpty ? userId : FirebaseManager.shared.resolvedUserId
        if enableHealth, !resolvedId.isEmpty {
            await healthSync.ensureSynced(userId: resolvedId)
        }
        let peakStart = UserDefaults.standard.integer(forKey: "peakStartHour")
        let resolvedName = UserLifeProfileStore.resolvedDisplayName()
        await shell.refreshContext(
            userId: resolvedId,
            userName: resolvedName,
            peakStartHour: peakStart > 0 ? peakStart : 9
        )
        await briefingVM.refresh(
            brainVM: brainVM,
            tasksVM: tasksVM,
            userId: resolvedId,
            userName: resolvedName,
            healthKitAvailable: enableHealth && HealthManager().isAvailable,
            heroBriefing: shell.contextOrchestrator.briefing?.hero,
            brainDecision: shell.contextOrchestrator.brainState?.decision,
            lifeSnapshot: shell.contextOrchestrator.snapshot,
            lifeTimelineEvents: shell.contextOrchestrator.lifeTimelineEvents,
            tomorrowLifeTimelineEvents: shell.contextOrchestrator.tomorrowLifeTimelineEvents
        )
        briefingVM.updateExecutiveCapacity(shell.contextOrchestrator.executiveCapacity)
    }
}

private struct BriefingScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
