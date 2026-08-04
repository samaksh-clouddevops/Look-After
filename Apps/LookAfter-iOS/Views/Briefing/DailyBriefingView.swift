import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth
import LookAfterData

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

    private let chaptersAnchorID = "briefing-chapters-start"

    private var showsScrollHint: Bool {
        scrollOffset < 40
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PremiumBackground()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        firstViewport(onContinue: {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(chaptersAnchorID, anchor: .top)
                            }
                        })
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
            }

            if showsScrollHint {
                scrollHintOverlay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsScrollHint)
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
        .accessibilityIdentifier("screen-briefing")
    }

    // MARK: - First viewport

    private func firstViewport(onContinue: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                headerBar
                BriefingGreetingHeader(greeting: briefingVM.greeting)
            }

            LAExecutiveBriefingCard(
                summaryLines: briefingVM.dayHeroSummaryLines,
                isLoading: briefingVM.isLoadingDayHeroSummary,
                onContinue: onContinue
            )
            .featureTourAnchor(.briefingHero)

            todayAtAGlanceSection
        }
        .padding(.horizontal, DesignSystem.BriefingViewport.sectionHorizontal)
        .safeAreaPadding(.top, DesignSystem.spacingSM)
        .padding(.bottom, DesignSystem.spacingSM)
    }

    private var scrollHintOverlay: some View {
        Text("↓ Scroll for more")
            .textStyleCaption(color: DesignSystem.textSecondary)
            .padding(.horizontal, DesignSystem.spacingMD)
            .padding(.vertical, DesignSystem.spacingSM)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(
                        color: DesignSystem.shadowElevated.opacity(0.12),
                        radius: 12,
                        y: 4
                    )
            )
            .padding(.bottom, DesignSystem.spacingMD)
            .accessibilityLabel("Scroll for more")
            .accessibilityHint("Scroll down to see sleep, tasks, and health")
    }

    @ViewBuilder
    private var todayAtAGlanceSection: some View {
        BriefingSectionCard(title: "Today at a Glance") {
            if glanceEvents.isEmpty {
                Text("Nothing fixed on the calendar yet.")
                    .textStyleCaption()
            } else {
                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(glanceEvents) { event in
                        LABriefingGlanceRow(
                            title: event.title,
                            timeRange: event.timeRange,
                            dotColor: event.dotColor,
                            action: onOpenToday
                        )
                    }
                }
            }
        }
        .padding(.top, DesignSystem.spacingSM)
        .accessibilityIdentifier("briefing-today-at-glance")
    }

    private struct GlanceEvent: Identifiable {
        let id: String
        let title: String
        let timeRange: String
        let dotColor: Color
    }

    private var glanceEvents: [GlanceEvent] {
        shell.contextOrchestrator.lifeTimelineEvents
            .filter(\.isImportantCommitment)
            .sorted { $0.date < $1.date }
            .prefix(3)
            .map { event in
                GlanceEvent(
                    id: event.id,
                    title: event.title,
                    timeRange: event.scheduleRangeLabel,
                    dotColor: glanceColor(for: event.kind)
                )
            }
    }

    private func glanceColor(for kind: LifeTimelineEventKind) -> Color {
        switch kind {
        case .work, .meeting: return DesignSystem.focus
        case .health, .medication, .exercise, .recovery: return DesignSystem.health
        case .creative, .personal: return DesignSystem.reflection
        case .finance, .bill, .shopping: return DesignSystem.learning
        case .travel: return DesignSystem.travel
        case .habit, .relationship: return DesignSystem.relationships
        }
    }

    // MARK: - Scroll chapters (below the fold)

    private var scrollChapters: some View {
        VStack(spacing: DesignSystem.BriefingViewport.chapterSpacing) {
            Color.clear.frame(height: 1).id(chaptersAnchorID)

            BriefingChapterSection(
                title: "How you're doing",
                subtitle: snapshotPreviewHint,
                icon: "sun.max"
            ) {
                VStack(spacing: DesignSystem.spacingLG) {
                    BriefingSnapshotStrip(snapshot: briefingVM.healthSnapshot)
                    LifeGapsCard(gaps: briefingVM.lifeGaps, onOpenTimeline: onOpenToday)
                }
            }

            if hasSnapshotDetailsChapter {
                BriefingChapterSection(
                    title: "Tasks & numbers",
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
                    title: "Also on your radar",
                    subtitle: recommendationsChapterSubtitle,
                    icon: "sparkles"
                ) {
                    recommendationsChapterContent
                }
            }

            BriefingModuleInsightsCard(
                insights: briefingVM.moduleInsights,
                isLoading: briefingVM.isLoadingModuleInsights
            )

            Color.clear.frame(height: DesignSystem.BriefingViewport.scrollHintHeight)
        }
        .padding(.bottom, DesignSystem.spacingMD)
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
                BriefingHealthCard(
                    health: briefingVM.health,
                    compact: true,
                    showsTitle: false,
                    onConnectHealth: connectHealth
                )
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

    private var snapshotPreviewHint: String {
        let readiness = briefingVM.healthSnapshot.readinessLabel
        let pct = briefingVM.progress.dayCompletionPercent
        if pct > 0 {
            return "\(readiness) · \(pct)% done so far"
        }
        return readiness
    }

    private var snapshotChapterSubtitle: String {
        let pct = briefingVM.progress.dayCompletionPercent
        return "\(briefingVM.healthSnapshot.readinessLabel) · \(pct)% done"
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
        if !briefingVM.energy.peakFocusWindow.isEmpty {
            return "Open stretch · \(briefingVM.energy.peakFocusWindow)"
        }
        return "Calendar's clear"
    }

    private var recommendationsChapterSubtitle: String {
        if !briefingVM.alerts.isEmpty {
            return "\(briefingVM.alerts.count) thing\(briefingVM.alerts.count == 1 ? "" : "s") to look at"
        }
        return "Habits and suggestions"
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
