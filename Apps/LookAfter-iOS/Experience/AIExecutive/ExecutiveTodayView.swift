import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth

/// Home — one immersive hero surface; scroll reveals life-context previews.
struct ExecutiveTodayView: View {
    @EnvironmentObject private var shell: AppShellState
    @ObservedObject private var healthSync = HealthSyncService.shared
    @AppStorage("userName") private var userName = ""
    @AppStorage("peakStartHour") private var peakStartHour = 9
    @AppStorage("enableHealth") private var enableHealth = true

    let userId: String
    var onCapture: () -> Void
    var onSettings: () -> Void
    var onOpenHealth: () -> Void
    var onViewPlan: () -> Void
    var onOpenContinueSession: (ContinueSessionContext) -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var loadingProgress: Double = 0

    private var hero: HeroBriefing? { shell.contextOrchestrator.briefing?.hero }
    private var story: TodaysStory? { shell.contextOrchestrator.briefing?.todaysStory }
    private var resume: ResumeSnapshot? { shell.contextOrchestrator.resumeSnapshot }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                CinematicBackground()
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ScrollOffsetReporter()

                        heroZone(in: geo)

                        destinationScroll
                            .padding(.top, 24)
                    }
                    .padding(.bottom, geo.size.height * 0.08)
                }
                .coordinateSpace(name: "cinematicScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }

                minimalChrome
            }
        }
        .task(id: refreshToken) {
            loadingProgress = 0
            withAnimation(.easeInOut(duration: 0.8)) { loadingProgress = 0.55 }
            let resolvedName = UserLifeProfileStore.resolvedDisplayName()
            await shell.refreshContext(userId: userId, userName: resolvedName, peakStartHour: peakStartHour)
            withAnimation(.easeOut(duration: 0.35)) { loadingProgress = 1 }
        }
        .refreshable {
            let resolvedName = UserLifeProfileStore.resolvedDisplayName()
            await shell.refreshContext(userId: userId, userName: resolvedName, peakStartHour: peakStartHour)
        }
    }

    private var refreshToken: String {
        [
            userId,
            String(shell.tasksVM.tasks.count),
            shell.brainVM.flowSurface?.generatedAt.description ?? "",
            String(shell.brainVM.healthSummary?.totalSleepMinutes ?? 0),
            String(shell.brainVM.healthSummary?.stepCount ?? 0),
            String(describing: healthSync.syncPhase),
            healthSync.lastSyncDate?.description ?? "none"
        ].joined(separator: "-")
    }

    private var collapseProgress: CGFloat {
        min(max(-scrollOffset / 320, 0), 1)
    }

    private var minimalChrome: some View {
        HStack {
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DesignSystem.textMuted.opacity(0.7))
                    .frame(width: 40, height: 40)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func heroZone(in geo: GeometryProxy) -> some View {
        ZStack {
            if shell.contextOrchestrator.snapshot == nil || isAwaitingHealthData {
                loadingState
            } else if let hero {
                heroComposition(for: hero)
            }
        }
        .frame(minHeight: geo.size.height * DesignSystem.heroViewportRatio)
        .scaleEffect(1 - collapseProgress * 0.04, anchor: .top)
        .opacity(1 - collapseProgress * 0.12)
    }

    private var isAwaitingHealthData: Bool {
        guard enableHealth, healthSync.isHealthEnabled, UserLifeProfileStore.hasCompletedOnboarding else {
            return false
        }
        if healthSync.isSyncing || healthSync.isConnectingForSetup || shell.isBootstrappingFreshStart {
            return true
        }
        return shell.brainVM.healthSummary == nil && healthSync.lastSyncDate == nil
    }

    private func heroComposition(for hero: HeroBriefing) -> some View {
        let task = resolveTask(hero.action.taskID)
        let frame = LifeContextFrameBuilder.build(resume: resume, task: task)
        let concreteLine = LifeContextFrameBuilder.heroConcreteLine(briefing: hero)
        let contextMeta = LifeContextFrameBuilder.metaLine(resume: resume, task: task)

        return IntegratedHeroComposition(
            greeting: hero.greeting,
            concreteLine: concreteLine,
            outcomeTitle: hero.buttonLabel,
            durationLabel: hero.supportingLine,
            contextMeta: contextMeta,
            frame: frame,
            whyNowReasons: hero.whyNowReasons,
            contextLine: hero.contextLine,
            lowConfidencePrompt: hero.lowConfidencePrompt,
            onContinue: { perform(hero.action, hero: hero) }
        )
    }

    private var destinationScroll: some View {
        VStack(spacing: 36) {
            if story?.isReady == true, !dayPreviewRows.isEmpty {
                DayPreviewCard(rows: dayPreviewRows, action: onViewPlan)
            }

            RememberPreviewCard(notePreview: resume?.lastNote, action: onCapture)

            if hero?.insights.contains(where: { $0.sourceKind == .sleep }) == true {
                SleepPreviewCard(sleepLabel: sleepLabel, action: onOpenHealth)
            }
        }
        .padding(.horizontal, 20)
    }

    private var dayPreviewRows: [DayPreviewRow] {
        LifeContextFrameBuilder.dayPreviewRows(
            timelineItems: shell.contextOrchestrator.lifeTimelineEvents,
            storySegments: story?.segments ?? []
        )
    }

    private var sleepLabel: String? {
        LifeContextFrameBuilder.sleepHoursLabel(from: shell.brainVM.healthSummary)
    }

    private func whyNow(for hero: HeroBriefing) -> some View {
        WhyThisAffordance(
            reasons: hero.whyNowReasons,
            contextLine: hero.contextLine,
            durationLabel: nil,
            insights: hero.insights,
            onOpenInsight: { insight in
                switch insight.destination {
                case .healthSleep, .healthOverview: onOpenHealth()
                default: break
                }
            }
        )
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            MeaningfulProgressView(
                heading: isAwaitingHealthData ? "Syncing your health data:" : "Getting ready:",
                steps: isAwaitingHealthData ? healthLoadingSteps() : HumanLanguage.homeLoadingSteps(),
                progress: loadingProgress
            )
            Spacer()
        }
    }

    private func healthLoadingSteps() -> [String] {
        if let label = healthSync.currentStepLabel, !label.isEmpty {
            return [label, "Updating Today with sleep & energy"]
        }
        return [
            "Reading Apple Health",
            "Building your energy picture",
            "Updating Today"
        ]
    }

    private func perform(_ action: ContextAction, hero: HeroBriefing) {
        switch action.kind {
        case .openContinueSession, .continueTask, .resumeSession:
            performContinue(from: hero, taskID: action.taskID)
        case .beginWork, .startTask:
            performBegin(from: hero, taskID: action.taskID)
        case .viewPlan: onViewPlan()
        case .openHealthDetail: onOpenHealth()
        case .openShopping: break
        case .openCoach, .openBrain: onCapture()
        }
    }

    private func performContinue(from hero: HeroBriefing, taskID: String? = nil) {
        let task = resolveTask(taskID)
        let snapshot = shell.contextOrchestrator.snapshot
            ?? LifeContextSnapshot(currentEnergy: 0.7, availableTimeMinutes: 60)

        let context = ContinueSessionContext.buildOrFallback(
            from: resume,
            task: task,
            snapshot: snapshot,
            healthSummary: shell.brainVM.healthSummary,
            insights: hero.insights,
            confidenceScore: hero.confidenceScore,
            fallbackTitle: hero.actionLine
        )
        onOpenContinueSession(context)
    }

    private func performBegin(from hero: HeroBriefing, taskID: String?) {
        let task = resolveTask(taskID)
        let snapshot = shell.contextOrchestrator.snapshot
            ?? LifeContextSnapshot(currentEnergy: 0.7, availableTimeMinutes: 60)
        let working = WorkingContext(kind: .task, title: task?.title ?? hero.actionLine, taskID: task?.id)
        let context = ContinueSessionContext.buildOrFallback(
            from: resume,
            task: task,
            snapshot: snapshot,
            healthSummary: shell.brainVM.healthSummary,
            insights: hero.insights,
            confidenceScore: hero.confidenceScore,
            fallbackTitle: hero.actionLine
        )
        onOpenContinueSession(context)
    }

    private func resolveTask(_ id: String?) -> LifeTask? {
        guard let id else { return shell.contextOrchestrator.snapshot?.currentMission }
        return shell.tasksVM.tasks.first { $0.id == id }
            ?? shell.brainVM.topTasks.first { $0.id == id }
            ?? shell.contextOrchestrator.snapshot?.currentMission
    }
}
