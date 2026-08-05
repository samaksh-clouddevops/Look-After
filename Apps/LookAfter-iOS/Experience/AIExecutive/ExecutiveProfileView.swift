import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth

/// Profile — capacity at a glance, routines, and path to insights. Settings live in a sheet.
struct ExecutiveProfileView: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRaw = AppAppearanceMode.system.rawValue

    let userId: String

    @State private var showSettings = false
    @State private var showInsights = false
    @State private var showModules = false
    @State private var showInbox = false
    #if DEBUG
    @State private var showBrainInspector = false
    #endif
    @State private var showResetAlert = false
    @State private var isResetting = false
    @State private var resetComplete = false

    private let bottomNavClearance: CGFloat = 96

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

            HStack(spacing: 0) {
                Button(action: toggleAppearance) {
                    Image(systemName: isEffectivelyDark ? "moon.fill" : "sun.max.fill")
                        .font(.dsIcon())
                        .foregroundColor(DesignSystem.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("you-appearance-toggle")
                .accessibilityLabel(isEffectivelyDark ? "Switch to light mode" : "Switch to dark mode")

                Button(action: {
                    showSettings = true
                }, label: {
                    Image(systemName: "gearshape")
                        .font(.dsIcon())
                        .foregroundColor(DesignSystem.textSecondary)
                        .frame(width: 44, height: 44)
                })
                .accessibilityLabel("Settings")
            }
            .padding(.trailing, DesignSystem.screenHorizontal - 8)
            .padding(.top, DesignSystem.spacingSM)
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
        #if DEBUG
        .sheet(isPresented: $showBrainInspector) {
            BrainInspectorView()
                .environmentObject(shell)
        }
        #endif
        .alert("Factory Reset \(UserFacingCopy.productName)?", isPresented: $showResetAlert, actions: {
            Button("Erase Everything", role: .destructive) {
                Task { await performFactoryReset() }
            }
            Button("Cancel", role: .cancel) {}
        }, message: {
            Text("Deletes all tasks, timeline, AI memory, health cache, learned behavior, and modules on this device and in the cloud. Your account and API keys are preserved. This cannot be undone.")
        })
        .alert("Factory reset complete", isPresented: $resetComplete, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text("\(UserFacingCopy.productName) is starting fresh. Health and calendar will re-import automatically.")
        })
        .accessibilityIdentifier("screen-you")
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        HStack(alignment: .center, spacing: DesignSystem.spacingMD) {
            ZStack {
                Circle()
                    .fill(DesignSystem.backgroundSecondary)
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

    private var lifeStateCard: some View {
        ElevatedSurface(padding: DesignSystem.cardPaddingMin) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Text("Life State")
                    .textStyleSectionLabel()

                LAProgressBar(label: "Energy", progress: energyProgress)
                LAProgressBar(label: "Focus", progress: focusProgress)
                LAProgressBar(label: "Wellbeing", progress: wellbeingProgress)

                Button(action: {
                    showInsights = true
                }, label: {
                    Text("See all insights →")
                        .textStyleCaption(color: DesignSystem.focus)
                })
                .buttonStyle(.plain)
            }
        }
    }

    private var energyProgress: Double {
        bandProgress(shell.briefingVM.executiveCapacity.band)
    }

    private var focusProgress: Double {
        let pct = shell.briefingVM.progress.dayCompletionPercent
        if pct > 0 { return Double(pct) / 100.0 }
        return max(0.35, energyProgress - 0.08)
    }

    private var wellbeingProgress: Double {
        if shell.briefingVM.sleep.isAvailable, let hours = shell.briefingVM.sleep.totalHours {
            return min(max(hours / 8.0, 0.2), 1.0)
        }
        return max(0.4, energyProgress)
    }

    private func bandProgress(_ band: ExecutiveCapacityBand) -> Double {
        switch band {
        case .peakFocus: return 0.92
        case .goodCapacity: return 0.78
        case .moderateCapacity: return 0.62
        case .lowCapacity: return 0.42
        case .recoveryMode: return 0.28
        }
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
                .textStyleCaption()

            if routineTasks.isEmpty {
                Text("Daily routines appear here once seeded.")
                    .textStyleCaption()
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
                    .textStyleCaption()
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(status)")
    }

    // MARK: - Settings sheet

    private var settingsSheet: some View {
        NavigationStack {
            List {
                integrationsSection
                statsSection
                #if DEBUG
                debugSection
                #endif
                developerResetSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(DesignSystem.spacingMD)
            .scrollContentBackground(.hidden)
            .background(DesignSystem.backgroundPrimary)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var developerResetSection: some View {
        Section(content: {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Text("Erases all app data and behaves like a fresh install. Preserves your account and API keys only.")
                    .textStyleCaption(color: DesignSystem.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive, action: {
                    showResetAlert = true
                }, label: {
                    HStack {
                        Label("Factory Reset", systemImage: "arrow.counterclockwise.circle.fill")
                        Spacer()
                        if isResetting {
                            ProgressView()
                                .scaleEffect(0.85)
                        }
                    }
                })
                .disabled(isResetting)
            }
            .padding(.vertical, 4)
            .listRowBackground(DesignSystem.backgroundSecondary)
        }, header: {
            Text("Developer")
        })
    }

    private var isEffectivelyDark: Bool {
        switch AppAppearanceMode(rawValue: appearanceRaw) ?? .system {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    private func toggleAppearance() {
        HapticManager.impact(.light)
        appearanceRaw = isEffectivelyDark
            ? AppAppearanceMode.light.rawValue
            : AppAppearanceMode.dark.rawValue
    }

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

    #if DEBUG
    private var debugSection: some View {
        Section(content: {
            Button(action: {
                showBrainInspector = true
            }, label: {
                Label("Brain Inspector", systemImage: "ladybug.fill")
            })
            .listRowBackground(DesignSystem.backgroundSecondary)
        }, header: {
            Text("Debug Tools")
        }, footer: {
            Text("Inspect Life State, intent, simulations, cost, and decision history.")
        })
    }
    #endif

    private var integrationsSection: some View {
        Section("Integrations") {
            NavigationLink(destination: {
                SettingsView()
                    .environmentObject(shell)
            }, label: {
                Label("Settings & API Keys", systemImage: "gearshape.fill")
            })
            .accessibilityIdentifier("nav-open-settings")
            .listRowBackground(DesignSystem.backgroundSecondary)
        }
    }

    private var statsSection: some View {
        Section("Today") {
            statRow("Open tasks", value: "\(shell.tasksVM.activeTasks.count)")
            statRow("Done today", value: "\(shell.tasksVM.completedToday.count)")
        }
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(DesignSystem.textSecondary)
        }
        .listRowBackground(DesignSystem.backgroundSecondary)
    }
}
