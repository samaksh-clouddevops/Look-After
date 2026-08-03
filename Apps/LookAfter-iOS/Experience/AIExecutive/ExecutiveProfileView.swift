import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth

/// Profile, settings, integrations, and feature flags.
struct ExecutiveProfileView: View {
    @EnvironmentObject private var shell: AppShellState

    let userId: String

    @State private var showInsights = false
    @State private var showModules = false
    #if DEBUG
    @State private var showBrainInspector = false
    #endif
    @State private var showResetAlert = false
    @State private var isResetting = false
    @State private var resetComplete = false

    private let bottomNavClearance: CGFloat = 96

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                List {
                    lifeStateSection
                    integrationsSection
                    statsSection
                    classicModulesSection
                    #if DEBUG
                    debugSection
                    #endif
                    developerResetSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: bottomNavClearance)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showInsights) {
                InsightsDashboardView(brain: shell.brain, userId: userId)
            }
            .sheet(isPresented: $showModules) {
                AllModulesGridView(modulesVM: shell.modulesVM)
            }
            #if DEBUG
            .sheet(isPresented: $showBrainInspector) {
                BrainInspectorView()
                    .environmentObject(shell)
            }
            #endif
            .alert("Factory Reset \(UserFacingCopy.productName)?", isPresented: $showResetAlert) {
                Button("Erase Everything", role: .destructive) {
                    Task { await performFactoryReset() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes all tasks, timeline, AI memory, health cache, learned behavior, and modules on this device and in the cloud. Your account and API keys are preserved. This cannot be undone.")
            }
            .alert("Factory reset complete", isPresented: $resetComplete) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(UserFacingCopy.productName) is starting fresh. Health and calendar will re-import automatically.")
            }
        }
        .accessibilityIdentifier("screen-executive-profile")
    }

    private var developerResetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Text("Erases all app data and behaves like a fresh install. Preserves your account and API keys only.")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    HStack {
                        Label("Factory Reset", systemImage: "arrow.counterclockwise.circle.fill")
                        Spacer()
                        if isResetting {
                            ProgressView()
                                .scaleEffect(0.85)
                        }
                    }
                }
                .disabled(isResetting)
            }
            .padding(.vertical, 4)
            .listRowBackground(DesignSystem.backgroundSecondary)
        } header: {
            Text("Developer")
        }
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
        Section {
            Button {
                showBrainInspector = true
            } label: {
                Label("Brain Inspector", systemImage: "ladybug.fill")
            }
            .listRowBackground(DesignSystem.backgroundSecondary)
        } header: {
            Text("Debug Tools")
        } footer: {
            Text("Inspect Life State, intent, simulations, cost, and decision history.")
        }
    }
    #endif

    private var lifeStateSection: some View {
        Section {
            LifeStateMetricsGrid(
                energy: shell.briefingVM.executiveCapacity.band.displayLabel,
                recovery: shell.briefingVM.sleep.isAvailable ? String(format: "%.1fh", shell.briefingVM.sleep.totalHours ?? 0) : "—",
                habits: "\(shell.briefingVM.habits.filter(\.isCompletedToday).count)/\(max(shell.briefingVM.habits.count, 1))",
                goals: "\(shell.tasksVM.completedToday.count) done"
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Life State")
        } footer: {
            Text("Energy, recovery, habits, and goals at a glance.")
        }
    }

    private var integrationsSection: some View {
        Section("Integrations") {
            NavigationLink {
                SettingsView()
                    .environmentObject(shell)
            } label: {
                Label("Settings & API Keys", systemImage: "gearshape.fill")
            }
            .accessibilityIdentifier("nav-open-settings")
            .listRowBackground(DesignSystem.backgroundSecondary)

            Button { showInsights = true } label: {
                Label("Statistics & Insights", systemImage: "chart.xyaxis.line")
            }
            .listRowBackground(DesignSystem.backgroundSecondary)
        }
    }

    private var statsSection: some View {
        Section("Today") {
            statRow("Open tasks", value: "\(shell.tasksVM.activeTasks.count)")
            statRow("Done today", value: "\(shell.tasksVM.completedToday.count)")
            statRow("Inbox", value: "\(shell.inboxVM.unprocessedCount) to review")
        }
    }

    private var classicModulesSection: some View {
        Section {
            Button { showModules = true } label: {
                Label("Everything else", systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("nav-open-modules")
            .listRowBackground(DesignSystem.backgroundSecondary)
        } footer: {
            Text("Finance, shopping, relationships, and other areas are still here.")
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

private struct LifeStateMetricsGrid: View {
    let energy: String
    let recovery: String
    let habits: String
    let goals: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingMD) {
            LifeStateMetricRing(title: "Energy", value: energy, color: DesignSystem.health)
            LifeStateMetricRing(title: "Recovery", value: recovery, color: DesignSystem.focus)
            LifeStateMetricRing(title: "Habits", value: habits, color: DesignSystem.reflection)
            LifeStateMetricRing(title: "Goals", value: goals, color: DesignSystem.learning)
        }
        .padding(DesignSystem.cardPaddingMin)
    }
}

private struct LifeStateMetricRing: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: DesignSystem.spacingSM) {
            ZStack {
                Circle()
                    .stroke(DesignSystem.divider, lineWidth: 6)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.dsCaption(weight: .bold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(title)
                .font(.dsMetadata(weight: .semibold))
                .foregroundColor(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
