import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth

/// Profile, settings, integrations, and feature flags.
struct ExecutiveProfileView: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var experience: ExperienceModeController

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
                    experienceSection
                    integrationsSection
                    statsSection
                    classicModulesSection
                    #if DEBUG
                    debugSection
                    #endif
                    developerResetSection
                }
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
            .listRowBackground(Color.white.opacity(0.05))
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
            .listRowBackground(Color.white.opacity(0.05))
        } header: {
            Text("Debug Tools")
        } footer: {
            Text("Inspect Life State, intent, simulations, cost, and decision history.")
        }
    }
    #endif

    private var experienceSection: some View {
        Section {
            Picker("Experience", selection: Binding(
                get: { experience.mode },
                set: { experience.setMode($0) }
            )) {
                ForEach(ExperienceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .listRowBackground(Color.white.opacity(0.05))

            Toggle(isOn: Binding(
                get: { experience.isAIExecutive },
                set: { experience.setMode($0 ? .aiExecutive : .classic) }
            )) {
                Label("Companion layout", systemImage: "sparkles.rectangle.stack")
            }
            .tint(DesignSystem.accentPrimary)
            .listRowBackground(Color.white.opacity(0.05))
        } header: {
            Text("Experience")
        } footer: {
            Text("Switch instantly — your tasks, health, and modules stay the same.")
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
            .listRowBackground(Color.white.opacity(0.05))

            Button { showInsights = true } label: {
                Label("Statistics & Insights", systemImage: "chart.xyaxis.line")
            }
            .listRowBackground(Color.white.opacity(0.05))
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
            .listRowBackground(Color.white.opacity(0.05))
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
        .listRowBackground(Color.white.opacity(0.05))
    }
}
