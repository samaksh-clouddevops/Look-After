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
    var onPostWake: (() -> Void)?
    var isPostWake: Bool = false
    var onDismissPostWake: (() -> Void)?

    @State private var showCustomization = false
    @State private var showHealthConnectSheet = false
    @State private var showHealthVerification = false
    @State private var showHealthTroubleshooting = false
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
                        Color.clear
                            .frame(height: 0)
                            .id(AppFeatureTourAnchorID.briefingScrollTop.rawValue)

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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsScrollHint {
                        scrollHintOverlay
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .tourScrollToAnchor)) { note in
                    guard let raw = note.userInfo?[TourScrollUserInfoKey.anchorID] as? String else { return }
                    let scrollAnchor = note.userInfo?[TourScrollUserInfoKey.scrollAnchor] as? String ?? "center"
                    withAnimation(.easeInOut(duration: 0.3)) {
                        switch raw {
                        case AppFeatureTourAnchorID.briefingHero.rawValue:
                            if scrollAnchor == "top" {
                                proxy.scrollTo(AppFeatureTourAnchorID.briefingScrollTop.rawValue, anchor: .top)
                            } else {
                                proxy.scrollTo(AppFeatureTourAnchorID.briefingHero.rawValue, anchor: .center)
                            }
                        case AppFeatureTourAnchorID.briefingHealthStrip.rawValue:
                            proxy.scrollTo(AppFeatureTourAnchorID.briefingHealthStrip.rawValue, anchor: .center)
                        default:
                            break
                        }
                    }
                }
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
        .onAppear {
            healthSync.refreshConnectionStatus(userId: userId, healthSummary: brainVM.healthSummary)
        }
        .sheet(isPresented: $showHealthVerification) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: DesignSystem.spacingMD) {
                        if let status = healthSync.connectionStatus {
                            HealthStatusBanner(
                                status: status,
                                style: .full,
                                onPrimaryAction: { handleHealthPrimaryAction(status.primaryAction) },
                                onLearnMore: { showHealthTroubleshooting = true }
                            )
                        }
                        if let report = healthSync.verificationReport {
                            HealthVerificationReportView(report: report)
                        }
                    }
                    .padding(DesignSystem.spacingLG)
                }
                .background(DesignSystem.backgroundPrimary.ignoresSafeArea())
                .navigationTitle("Health status")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showHealthVerification = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showHealthTroubleshooting) {
            NavigationStack {
                HealthTroubleshootingView(healthSync: healthSync, userId: userId)
                    .environmentObject(shell)
            }
        }
        .accessibilityIdentifier("screen-briefing")
    }

    // MARK: - First viewport

    private func firstViewport(onContinue: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                headerBar
                // Time greeting only — Chief narrative is the body (no chat/mic here).
                BriefingGreetingHeader(greeting: briefingVM.greeting)
            }

            // Hero — bullet summary lines (body size), same as main.
            LAExecutiveBriefingCard(
                summaryLines: briefingVM.dayHeroSummaryLines,
                buttonTitle: "Continue to today",
                isLoading: briefingVM.isLoadingDayHeroSummary,
                onContinue: onContinue
            )
            .featureTourAnchor(.briefingHero, cornerRadius: DesignSystem.radiusLG)
            .id(AppFeatureTourAnchorID.briefingHero.rawValue)

            if isPostWake, let onPostWake {
                postWakeCard(onReplan: onPostWake, onDismiss: onDismissPostWake)
            }

            todayAtAGlanceSection
        }
        .padding(.horizontal, DesignSystem.BriefingViewport.sectionHorizontal)
        .safeAreaPadding(.top, DesignSystem.spacingMD)
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
        shell.timelineService.snapshot.today
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

    @ViewBuilder
    private func postWakeCard(onReplan: @escaping () -> Void, onDismiss: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(DesignSystem.accentPrimary)
                Text("Just woke up?")
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                Spacer()
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("I can replan what's left — defer what you missed and keep today realistic.")
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textSecondary)
            Button(action: onReplan) {
                Text("Replan my day")
                    .font(.dsCaption(weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
        .accessibilityIdentifier("briefing-post-wake-card")
    }

    // MARK: - Scroll chapters (below the fold)

    private var scrollChapters: some View {
        LazyVStack(spacing: DesignSystem.BriefingViewport.chapterSpacing) {
            Color.clear.frame(height: 1).id(chaptersAnchorID)

            BriefingChapterSection(
                title: "How you're doing",
                subtitle: snapshotPreviewHint,
                icon: "sun.max"
            ) {
                VStack(spacing: DesignSystem.spacingLG) {
                    if let status = healthSync.connectionStatus, status.needsAttention {
                        HealthStatusBanner(
                            status: status,
                            style: .compact,
                            onPrimaryAction: { handleHealthPrimaryAction(status.primaryAction) },
                            onSeeDetails: { showHealthVerification = true },
                            onLearnMore: { showHealthTroubleshooting = true }
                        )
                    }
                    BriefingSnapshotStrip(
                        snapshot: briefingVM.healthSnapshot,
                        healthNeedsAttention: healthSync.connectionStatus?.needsAttention ?? false
                    )
                        .featureTourAnchor(.briefingHealthStrip, cornerRadius: DesignSystem.radiusMD)
                        .id(AppFeatureTourAnchorID.briefingHealthStrip.rawValue)
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
                BriefingSleepCard(
                    sleep: briefingVM.sleep,
                    compact: true,
                    connectionStatus: healthSync.connectionStatus,
                    onConnectHealth: connectHealth,
                    onHealthPrimaryAction: { handleHealthPrimaryAction(healthSync.connectionStatus?.primaryAction ?? .connect) },
                    onSeeHealthDetails: { showHealthVerification = true },
                    onLearnMore: { showHealthTroubleshooting = true }
                )
            }
            if isVisible(.energy) {
                ExecutiveCapacityCard(capacity: briefingVM.executiveCapacity, compact: true)
            }
            if isVisible(.health) {
                BriefingHealthCard(
                    health: briefingVM.health,
                    compact: true,
                    showsTitle: false,
                    connectionStatus: healthSync.connectionStatus,
                    onConnectHealth: connectHealth,
                    onHealthPrimaryAction: { handleHealthPrimaryAction(healthSync.connectionStatus?.primaryAction ?? .connect) },
                    onSeeHealthDetails: { showHealthVerification = true },
                    onLearnMore: { showHealthTroubleshooting = true }
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
                    briefingVM.toggleHabit(habit, tasksVM: tasksVM, userId: userId)
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

            Button(action: onCapture) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DesignSystem.backgroundElevated))
            }
            .accessibilityLabel("Capture a thought")

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
            healthSync.lastSyncDate?.timeIntervalSince1970.description ?? "0",
            brainVM.flowSurface?.generatedAt.description ?? "",
            shell.contextOrchestrator.briefing?.generatedAt.description ?? "",
            String(brainVM.cognitiveSnapshot?.executiveFunctionScore ?? 0),
            String(brainVM.cognitiveSnapshot?.energyScore ?? 0),
        ].joined(separator: "-")
    }

    private func connectHealth() {
        guard enableHealth else { return }
        showHealthConnectSheet = true
    }

    private func syncHealthNow() {
        guard enableHealth else { return }
        Task {
            let resolvedId = FirebaseManager.shared.resolvedUserId.isEmpty ? userId : FirebaseManager.shared.resolvedUserId
            await healthSync.syncHealthData(userId: resolvedId)
            healthSync.refreshConnectionStatus(userId: resolvedId, healthSummary: brainVM.healthSummary)
        }
    }

    private func handleHealthPrimaryAction(_ action: HealthStatusAction) {
        HealthStatusActionHandler.perform(
            action,
            onConnect: connectHealth,
            onSync: syncHealthNow,
            onOpenSettings: onOpenSettings
        )
    }

    private func reload() async {
        let resolvedId = FirebaseManager.shared.resolvedUserId.isEmpty ? userId : FirebaseManager.shared.resolvedUserId
        if enableHealth, !resolvedId.isEmpty {
            await healthSync.ensureSynced(userId: resolvedId)
        }
        let peakStart = UserLifeProfileStore.load().peakStartHour
        let resolvedName = UserLifeProfileStore.resolvedDisplayName()
        await shell.refreshContext(
            userId: resolvedId,
            userName: resolvedName,
            peakStartHour: peakStart > 0 ? peakStart : 9
        )
    }
}

private struct BriefingScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
