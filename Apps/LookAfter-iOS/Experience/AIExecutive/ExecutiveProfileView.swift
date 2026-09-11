import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth
import LookAfterData

/// Profile — capacity at a glance, routines, and path to insights. Settings live in a sheet.
struct ExecutiveProfileView: View {
    @EnvironmentObject private var shell: AppShellState
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRaw = AppAppearanceMode.system.rawValue

    let userId: String
    var opensReviewOnAppear: Bool = false

    @State private var showSettings = false
    @State private var showInsights = false
    @State private var showModules = false
    @State private var showInbox = false
    @State private var showWeeklyReview = false
    @State private var weeklyAIRetrospective: WeeklyAIRetrospective?
    @State private var weeklyReviewSummaryCache: WeeklyReviewSummary?
    @State private var weeklyReviewRefreshGeneration = 0
    #if DEBUG
    @State private var showBrainInspector = false
    @State private var showResetAlert = false
    @State private var isResetting = false
    @State private var resetComplete = false
    #endif

    /// Extra scroll padding so Routines clear the Liquid Glass tab bar (on top of root safeAreaInset).
    private let bottomNavClearance: CGFloat = 160

    private var displayName: String {
        UserLifeProfileStore.resolvedDisplayName()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PremiumBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                    Text("You")
                        .textStyleScreenTitle()

                    profileHeader

                    lifeStateCard

                    lifeAreasSection

                    routinesSection

                    Color.clear.frame(height: bottomNavClearance)
                }
                .padding(.horizontal, DesignSystem.screenHorizontal)
                .padding(.top, DesignSystem.spacingSM)
            }

            HStack(spacing: LAChromeMetrics.toolbarGap) {
                LAToolbarIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Settings",
                    action: { showSettings = true }
                )
            }
            .padding(.trailing, DesignSystem.screenHorizontal - 8)
            .padding(.top, DesignSystem.spacingSM)
        }
        .refreshable {
            await refreshYouTabSurface()
        }
        .task {
            await refreshYouTabSurface()
            if opensReviewOnAppear {
                showWeeklyReview = true
            }
        }
        .onChange(of: shell.tasksVM.tasksContentRevision) { _, _ in
            refreshYouTabProgress()
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showInsights) {
            InsightsDashboardView(brain: shell.brain, userId: userId)
        }
        .sheet(isPresented: $showModules) {
            AllModulesGridView(modulesVM: shell.modulesVM, userId: userId)
                .environmentObject(shell)
        }
        .sheet(isPresented: $showInbox) {
            NavigationStack {
                InboxView(inboxVM: shell.inboxVM, userId: userId)
            }
        }
        .sheet(isPresented: $showWeeklyReview) {
            NavigationStack {
                WeeklyReviewView(
                    summary: displayedWeeklyReviewSummary,
                    aiRetrospective: weeklyAIRetrospective,
                    onRefresh: { await refreshWeeklyReview() }
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showWeeklyReview = false }
                    }
                }
            }
            .onAppear { recomputeWeeklyReviewSummary() }
        }
        #if DEBUG
        .sheet(isPresented: $showBrainInspector) {
            BrainInspectorView()
                .environmentObject(shell)
        }
        .alert("Factory Reset \(UserFacingCopy.productName)?", isPresented: $showResetAlert, actions: {
            Button("Erase Everything", role: .destructive) {
                Task { await performFactoryReset() }
            }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text("Deletes all tasks, timeline, AI memory, health cache, learned behavior, and modules on this device and in the cloud. Your account and license are preserved. This cannot be undone.")
        })
        .alert("Factory reset complete", isPresented: $resetComplete, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text("\(UserFacingCopy.productName) is starting fresh. Health and calendar will re-import automatically.")
        })
        #endif
        .accessibilityIdentifier("screen-you")
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        HStack(alignment: .center, spacing: DesignSystem.spacingMD) {
            ZStack {
                Circle()
                    .fill(DesignSystem.contentSurface)
                    .frame(width: 48, height: 48)
                Text(profileInitials)
                    .font(.dsCardTitle())
                    .foregroundColor(DesignSystem.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName.isEmpty ? "You" : displayName)
                    .textStyleCardTitle()
                Text("Keep going. You're building something great.")
                    .textStyleCaption(color: DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .featureTourAnchor(.youProfile, cornerRadius: DesignSystem.radiusMD)
        .id(AppFeatureTourAnchorID.youProfile.rawValue)
    }

    private var profileInitials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined()
        return initials.isEmpty ? "Y" : initials.uppercased()
    }

    // MARK: - Life state

    private var lifeStateProgress: LifeStateProgressResolver.Progress {
        LifeStateProgressResolver.resolve(
            healthSnapshot: shell.briefingVM.healthSnapshot,
            sleep: shell.briefingVM.sleep
        )
    }

    private var lifeStateCard: some View {
        ElevatedSurface(padding: DesignSystem.cardPaddingMin) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Text("Life State")
                    .textStyleSectionLabel()

                LAProgressBar(label: "Energy", progress: lifeStateProgress.energy, barHeight: 12)
                LAProgressBar(label: "Focus", progress: lifeStateProgress.focus, barHeight: 12)
                LAProgressBar(label: "Wellbeing", progress: lifeStateProgress.wellbeing, barHeight: 12)

                Text(lifeStateCaption)
                    .textStyleCaption(color: DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: {
                    showInsights = true
                }, label: {
                    Text("See all insights →")
                        .textStyleCaption(color: DesignSystem.accentPrimary)
                })
                .buttonStyle(.plain)
            }
        }
    }

    private var lifeStateCaption: String {
        let snapshot = shell.briefingVM.healthSnapshot
        let energySuffix = snapshot.hasOvernightHealthSignal
            ? "\(snapshot.energyPercent)% energy"
            : "Est. \(snapshot.energyPercent)% energy"
        if snapshot.hasOvernightHealthSignal {
            return "\(snapshot.readinessLabel) · \(snapshot.recoveryLabel) · \(energySuffix)"
        }
        if shell.briefingVM.sleep.isAvailable, let hours = shell.briefingVM.sleep.totalHours {
            return "\(snapshot.readinessLabel) · \(String(format: "%.1fh", hours)) sleep · \(energySuffix)"
        }
        return "\(snapshot.readinessLabel) · \(energySuffix)"
    }

    // MARK: - Life areas

    private var lifeAreasSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text("Life areas")
                .textStyleSectionLabel()

            Button(action: { showInbox = true }, label: {
                DestinationTile(
                    title: "Inbox",
                    subtitle: "Review captured thoughts",
                    badge: shell.inboxVM.unprocessedCount > 0 ? "\(shell.inboxVM.unprocessedCount) to review" : nil
                )
            })
            .buttonStyle(PremiumPressStyle())
            .accessibilityIdentifier("you-inbox-tile")

            Button(action: { showWeeklyReview = true }, label: {
                DestinationTile(
                    title: "Review",
                    subtitle: "Weekly debrief and patterns",
                    badge: nil
                )
            })
            .buttonStyle(PremiumPressStyle())
            .accessibilityIdentifier("you-review-tile")
            .featureTourAnchor(.reviewHero, cornerRadius: DesignSystem.radiusMD)
            .id(AppFeatureTourAnchorID.reviewHero.rawValue)

            Button(action: { showModules = true }, label: {
                DestinationTile(
                    title: "Modules",
                    subtitle: "Finance, relationships, journal, and more",
                    badge: nil
                )
            })
            .buttonStyle(PremiumPressStyle())
            .accessibilityIdentifier("nav-open-modules")
        }
    }

    // MARK: - Routines

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text("Routines")
                .textStyleSectionLabel()
            Text("The ring fills as you complete each daily habit.")
                .textStyleCaption(color: DesignSystem.textSecondary)

            if routineTasks.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    Text("No daily routines yet")
                        .font(.dsBody(weight: .semibold))
                        .foregroundColor(DesignSystem.textSecondary)
                    Text("Routines tagged daily-routine show up here with a progress ring as you complete them.")
                        .textStyleCaption(color: DesignSystem.textSecondary)
                }
                .padding(DesignSystem.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .fill(DesignSystem.contentSurfaceElevated)
                )
            } else {
                ForEach(routineTasks) { task in
                    routineRow(task)
                }
            }
        }
    }

    private var routineTasks: [LifeTask] {
        let active = shell.tasksVM.tasks.filter {
            $0.tags.contains("daily-routine") && $0.status.isActive
        }
        let doneToday = shell.tasksVM.completedToday.filter {
            $0.tags.contains("daily-routine")
        }

        var merged: [String: LifeTask] = [:]
        for task in active {
            merged[normalizedRoutineKey(task.title)] = task
        }
        for task in doneToday {
            merged[normalizedRoutineKey(task.title)] = task
        }

        return merged.values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(4)
            .map { $0 }
    }

    private func normalizedRoutineKey(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func routineProgress(for task: LifeTask) -> Double {
        if task.status == .completed { return 1 }
        if shell.tasksVM.completedToday.contains(where: { $0.id == task.id }) { return 1 }
        if !task.steps.isEmpty { return task.progress }
        return 0
    }

    private func routineStatusLabel(for task: LifeTask) -> String {
        let progress = routineProgress(for: task)
        if progress >= 1 {
            return "Done today"
        }
        if !task.steps.isEmpty {
            let done = task.steps.filter(\.isCompleted).count
            return "\(done) of \(task.steps.count) steps done"
        }
        if let scheduled = task.scheduledTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Scheduled \(formatter.string(from: scheduled))"
        }
        return "Not yet today"
    }

    private func routineRow(_ task: LifeTask) -> some View {
        let progress = routineProgress(for: task)
        let status = routineStatusLabel(for: task)

        return HStack(spacing: DesignSystem.spacingMD) {
            LAProgressRing(
                progress: progress,
                diameter: 28,
                lineWidth: 3
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .textStyleCardTitle()
                Text(status)
                    .textStyleCaption(color: DesignSystem.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
                .fill(DesignSystem.contentSurface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(status)")
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(DesignSystem.contentSurface)
            .accessibilityIdentifier("you-appearance-toggle")
        }
    }

    // MARK: - Settings sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                appearanceSection
                integrationsSection
                statsSection
                #if DEBUG
                developerToolsSection
                #endif
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(DesignSystem.spacingMD)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.backgroundPrimary)
            .navigationTitle("You & app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.accentPrimary)
                        .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.large])
    }

    #if DEBUG
    private func performFactoryReset() async {
        isResetting = true
        await shell.performFactoryReset(
            userId: userId,
            healthSync: HealthSyncService.shared
        )
        isResetting = false
        resetComplete = true
        HapticManager.notification(.success)
    }

    /// Brain Inspector + Factory Reset — debug builds only (not production ADHD path).
    private var developerToolsSection: some View {
        Section(content: {
            Button(action: {
                showBrainInspector = true
            }, label: {
                Label("Brain Inspector", systemImage: "ladybug.fill")
            })
            .listRowBackground(DesignSystem.contentSurface)

            Button(role: .destructive, action: {
                showResetAlert = true
            }, label: {
                HStack {
                    Label("Factory Reset", systemImage: "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(DesignSystem.error)
                    Spacer()
                    if isResetting {
                        ProgressView()
                            .scaleEffect(0.85)
                    }
                }
            })
            .disabled(isResetting)
            .listRowBackground(DesignSystem.contentSurface)
        }, header: {
            Text("Developer")
        }, footer: {
            Text("Inspect Life State, intent, simulations, and decision history. Factory Reset erases all app data on this device and in the cloud; account and license are preserved.")
        })
    }
    #endif

    private var integrationsSection: some View {
        Section("Integrations") {
            NavigationLink(destination: {
                SettingsView()
                    .environmentObject(shell)
            }, label: {
                Label("Preferences", systemImage: "gearshape.fill")
            })
            .accessibilityIdentifier("nav-open-settings")
            .accessibilityLabel("Preferences")
            .listRowBackground(DesignSystem.contentSurface)
        }
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: DesignSystem.spacingLG) {
                todayMetric(title: "Open tasks", value: "\(shell.tasksVM.activeTasks.count)")
                todayMetric(title: "Done today", value: "\(shell.tasksVM.completedToday.count)")
            }
            .padding(.vertical, DesignSystem.spacingXS)
            .listRowBackground(DesignSystem.contentSurface)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .contain)
        } header: {
            Text("Today")
        }
    }

    private func todayMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.dsCardTitle())
                .foregroundStyle(DesignSystem.textPrimary)
                .contentTransition(.numericText())
            Text(title)
                .textStyleCaption(color: DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }

    private func refreshYouTabSurface() async {
        refreshYouTabProgress()
        await shell.inboxVM.loadItems(userId: userId)
    }

    private func refreshYouTabProgress() {
        let healthEnabled = UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true
        shell.briefingVM.refreshTaskProgress(
            brainVM: shell.brainVM,
            tasksVM: shell.tasksVM,
            healthKitAvailable: healthEnabled,
            lifeTimelineEvents: shell.timelineService.snapshot.today
        )
    }

    private var displayedWeeklyReviewSummary: WeeklyReviewSummary {
        weeklyReviewSummaryCache ?? LifeEngine.shared.weeklyReview(tasks: shell.tasksVM.schedulingContext)
    }

    private func recomputeWeeklyReviewSummary() {
        weeklyReviewSummaryCache = LifeEngine.shared.weeklyReview(tasks: shell.tasksVM.schedulingContext)
    }

    private func refreshWeeklyReview() async {
        shell.tasksVM.syncFromTaskStore()
        weeklyReviewRefreshGeneration += 1
        recomputeWeeklyReviewSummary()
        let behavior = await ProactiveActionsBuilder.loadBehaviorMemory()
        let analytics = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)
        weeklyAIRetrospective = await WeeklyAIRetrospectiveGenerator().generate(
            summary: displayedWeeklyReviewSummary,
            analytics: analytics,
            behaviorMemory: behavior
        )
    }
}
