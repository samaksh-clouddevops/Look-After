import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterHealth

/// Settings View — configure GLM API key, health tracking, ADHD features, and profile.
struct SettingsView: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("enableHealth") private var enableHealth: Bool = true
    @State private var lifeProfile = UserLifeProfileStore.load()
    @State private var lifeProfileMarkdown: String = ""
    @State private var structuredProfileSections = StructuredLifeProfileSections()
    @State private var profileOrganizeError: String?
    @State private var taskSyncMessage: String?
    @State private var isSyncingTasks = false
    @State private var cyclePreferences = CyclePreferencesStore.load()
    @AppStorage("targetSleepHours") private var targetSleepHours: Double = 8.0
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userEmail") private var userEmail: String = ""
    @AppStorage("adhdFocusChallenge") private var adhdFocusChallenge: String = "Task Initiation"
    @AppStorage("aiCoachTone") private var aiCoachTone: String = "Encouraging & Gentle"
    @AppStorage("userKeyGoals") private var userKeyGoals: String = ""
    @AppStorage("appCurrencySymbol") private var appCurrencySymbol: String = "₹"
    @AppStorage("focusDurationMinutes") private var focusDurationMinutes: Int = 25
    @AppStorage("pinNowToLockScreen") private var pinNowToLockScreen = false
    @AppStorage(FlowDirectorFeature.userDefaultsKey) private var enableFlowDirector = false
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRaw = AppAppearanceMode.system.rawValue

    private var appearance: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    private var useSystemAppearance: Binding<Bool> {
        Binding(
            get: { appearance.usesSystemSetting },
            set: { usesSystem in
                appearanceRaw = usesSystem
                    ? AppAppearanceMode.system.rawValue
                    : AppAppearanceMode.light.rawValue
            }
        )
    }

    private var darkModeEnabled: Binding<Bool> {
        Binding(
            get: { appearance.isDark },
            set: { isDark in
                appearanceRaw = isDark
                    ? AppAppearanceMode.dark.rawValue
                    : AppAppearanceMode.light.rawValue
            }
        )
    }
    
    @StateObject private var healthSync = HealthSyncService.shared
    @StateObject private var apiKeysVM = APIKeysSettingsViewModel()
    @State private var aiUsageSummary = GLMUsageSummary()
    
    private let focusChallenges = [
        "Task Initiation",
        "Time Blindness",
        "Task Paralysis / Overwhelm",
        "Hyperfocus Context Switching"
    ]
    
    private let coachTones = [
        "Encouraging & Gentle",
        "Direct & Action-Oriented",
        "Gamified & Energetic",
        "Socratic & Reflective"
    ]
    
    var body: some View {
        PremiumForm {
                // Account & Cloud Sync
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(DesignSystem.textMuted)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Your Name", text: $userName)
                                .font(.system(size: 18, weight: .semibold, design: .default))
                            
                            if let email = FirebaseManager.shared.userEmail, !email.isEmpty {
                                Text(email)
                                    .font(.system(size: 13, weight: .regular, design: .default))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "icloud.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignSystem.textMuted)
                                Text("Google/Apple Cloud Sync Active")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)
                    
                    Button(role: .destructive, action: {
                        try? FirebaseManager.shared.signOut()
                    }) {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)
                } header: {
                    Text("Account & Cloud Sync")
                } footer: {
                    Text("Leave blank to use the name from your Life Profile (e.g. \"I'm Alex…\").")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }

                Section {
                    Toggle(isOn: useSystemAppearance) {
                        Label("Match iPhone appearance", systemImage: "iphone")
                    }
                    .accessibilityIdentifier("settings-appearance-system-toggle")
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    if !appearance.usesSystemSetting {
                        Toggle(isOn: darkModeEnabled) {
                            Label("Dark Mode", systemImage: "moon.fill")
                        }
                        .accessibilityIdentifier("settings-dark-mode-toggle")
                        .listRowBackground(DesignSystem.backgroundSecondary)
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text(appearance.usesSystemSetting
                         ? "Look After follows your iPhone light or dark setting."
                         : "Dark Mode is controlled inside the app. Turn off “Match iPhone appearance” to change it here.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }

                Section {
                    Picker("Gender", selection: Binding(
                        get: { lifeProfile.gender ?? .preferNotToSay },
                        set: { newGender in
                            lifeProfile.gender = newGender
                            UserLifeProfileStore.save(lifeProfile)
                            if newGender != .female && cyclePreferences.isEnabled {
                                cyclePreferences.isEnabled = false
                                CyclePreferencesStore.save(cyclePreferences)
                            }
                        }
                    )) {
                        ForEach(UserGender.allCases) { gender in
                            Text(gender.label).tag(gender)
                        }
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Cycle tracking is available when you identify as female.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }

                // AI Executive Profile & Personalization
                Section {
                    Picker("Primary Focus Challenge", selection: $adhdFocusChallenge) {
                        ForEach(focusChallenges, id: \.self) { challenge in
                            Text(challenge).tag(challenge)
                        }
                    }
                    
                    Picker("Conversation tone", selection: $aiCoachTone) {
                        ForEach(coachTones, id: \.self) { tone in
                            Text(tone).tag(tone)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Goals & Focus Areas")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        
                        TextField("e.g. Launch Q3 deck, workout daily, read 20 mins", text: $userKeyGoals)
                            .font(.system(size: 14, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                } header: {
                    Text("Personal Profile")
                } footer: {
                    Text("This profile helps daily planning, task micro-steps, and chat adapt to your unique brain.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }
                
                // AI Configuration
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI Engine")
                                .font(.system(size: 14, weight: .semibold, design: .default))
                            Text("GLM \(GLMService.shared.configuration.defaultModel)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    if let active = apiKeysVM.activeKey {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Active API Key")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                Text("\(active.name) · \(active.maskedDisplay)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                            Spacer()
                            Image(systemName: active.status.iconName)
                                .foregroundColor(active.status == .active ? DesignSystem.success : DesignSystem.warning)
                        }
                        .listRowBackground(DesignSystem.backgroundSecondary)
                    }

                    NavigationLink {
                        GLMUsageSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("AI Usage", systemImage: "chart.bar.doc.horizontal")
                            Text(aiUsagePreviewText)
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)
                    .accessibilityIdentifier("settings-ai-usage")

                    NavigationLink {
                        GLMConfigurationSettingsView()
                    } label: {
                        Label("GLM Configuration", systemImage: "cpu")
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    NavigationLink {
                        APIKeysSettingsView()
                    } label: {
                        Label("Manage API Keys", systemImage: "key.fill")
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    Text("\(UserFacingCopy.productName) includes a default GLM key for first-run AI. Add your own key in API Keys to replace it, or set \(GLMConfiguration.apiKeyEnvVar) in the environment.")
                        .font(.system(size: 12, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                        .listRowBackground(DesignSystem.backgroundSecondary)
                } header: {
                    Text("AI Engine")
                } footer: {
                    Text("Keys are stored securely in the Keychain.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }
                
                // Preferences & Currency
                Section {
                    Picker("Default Currency", selection: $appCurrencySymbol) {
                        Text("INR (₹)").tag("₹")
                        Text("USD ($)").tag("$")
                        Text("EUR (€)").tag("€")
                        Text("GBP (£)").tag("£")
                    }
                    
                    Picker("Default Focus Duration", selection: $focusDurationMinutes) {
                        Text("15 minutes").tag(15)
                        Text("25 minutes").tag(25)
                        Text("30 minutes").tag(30)
                        Text("45 minutes").tag(45)
                        Text("60 minutes").tag(60)
                    }
                } header: {
                    Text("Preferences")
                }
                
                // Features
                Section {
                    Toggle(isOn: $enableHealth) {
                        Label("Health Tracking", systemImage: "heart.fill")
                    }
                    .tint(DesignSystem.accentPrimary)
                    .onChange(of: enableHealth) { _, enabled in
                        if enabled {
                            Task {
                                let userId = FirebaseManager.shared.resolvedUserId
                                await healthSync.syncHealthData(userId: userId)
                                await refreshAfterHealthSync(userId: userId)
                            }
                        }
                    }
                    
                    Toggle(isOn: $enableFlowDirector) {
                        Label("Suggested next steps", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .tint(DesignSystem.accentPrimary)
                } header: {
                    Text("Features")
                } footer: {
                    if enableFlowDirector {
                        Text("Picks your next task from calendar, energy, and deadlines — without generic category labels.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                
                if enableHealth {
                    Section {
                        HStack {
                            Image(systemName: "applewatch.watchface")
                                .font(.system(size: 28))
                                .foregroundColor(DesignSystem.textMuted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Apple Watch & Health")
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                Text("Sleep, HRV, steps, and heart rate via HealthKit")
                                    .font(.system(size: 12, design: .default))
                                    .foregroundColor(DesignSystem.textMuted)
                            }
                        }
                        .listRowBackground(DesignSystem.backgroundSecondary)
                        
                        if let lastSync = healthSync.lastSyncDate {
                            HStack {
                                Text("Last Synced")
                                Spacer()
                                Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                            .listRowBackground(DesignSystem.backgroundSecondary)
                        }
                        
                        if healthSync.isSyncing || !healthSync.syncSteps.isEmpty || healthSync.syncPhase == .failed {
                            HealthSyncProgressView(healthSync: healthSync, style: .full)
                                .listRowBackground(DesignSystem.backgroundSecondary)
                        } else if let message = healthSync.syncMessage {
                            Text(message)
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.textSecondary)
                                .listRowBackground(DesignSystem.backgroundSecondary)
                        }
                        
                        Button(action: {
                            Task {
                                let userId = FirebaseManager.shared.resolvedUserId
                                await healthSync.syncHealthData(userId: userId)
                                await refreshAfterHealthSync(userId: userId)
                            }
                        }) {
                            HStack {
                                if healthSync.isSyncing {
                                    Text("Syncing…")
                                } else if healthSync.canRetry {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry Sync")
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Sync Apple Watch Data Now")
                                }
                            }
                        }
                        .disabled(healthSync.isSyncing)
                        .listRowBackground(DesignSystem.backgroundSecondary)
                    } header: {
                        Text("Health Data Sync")
                    } footer: {
                        Text("\(UserFacingCopy.productName) reads from the iPhone Health app, which includes metrics recorded by your Apple Watch.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }

                if lifeProfile.gender == .female {
                Section {
                    Toggle(isOn: Binding(
                        get: { cyclePreferences.isEnabled },
                        set: { enabled in
                            cyclePreferences.isEnabled = enabled
                            CyclePreferencesStore.save(cyclePreferences)
                        }
                    )) {
                        Label("Track menstrual cycle", systemImage: "circle.circle.fill")
                    }
                    .tint(DesignSystem.accentPrimary)

                    if cyclePreferences.isEnabled {
                        NavigationLink {
                            CycleDashboardView()
                        } label: {
                            Label("Cycle dashboard", systemImage: "calendar.circle")
                        }
                        .listRowBackground(DesignSystem.backgroundSecondary)

                        Stepper("Cycle length: \(cyclePreferences.averageCycleLengthDays) days", value: Binding(
                            get: { cyclePreferences.averageCycleLengthDays },
                            set: {
                                cyclePreferences.averageCycleLengthDays = $0
                                CyclePreferencesStore.save(cyclePreferences)
                            }
                        ), in: 21...40)
                        .listRowBackground(DesignSystem.backgroundSecondary)

                        Stepper("Period length: \(cyclePreferences.averagePeriodLengthDays) days", value: Binding(
                            get: { cyclePreferences.averagePeriodLengthDays },
                            set: {
                                cyclePreferences.averagePeriodLengthDays = $0
                                CyclePreferencesStore.save(cyclePreferences)
                            }
                        ), in: 2...10)
                        .listRowBackground(DesignSystem.backgroundSecondary)

                        DatePicker("Last period start", selection: Binding(
                            get: { cyclePreferences.lastPeriodStart ?? Date() },
                            set: {
                                cyclePreferences.lastPeriodStart = Calendar.current.startOfDay(for: $0)
                                CyclePreferencesStore.save(cyclePreferences)
                            }
                        ), displayedComponents: .date)
                        .listRowBackground(DesignSystem.backgroundSecondary)
                    }
                } header: {
                    Text("Cycle tracking")
                } footer: {
                    Text("Optional. Includes menstrual data from Apple Health when enabled. \(UserFacingCopy.medicalDisclaimer)")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }
                }
                
                Section {
                    Toggle(isOn: $pinNowToLockScreen) {
                        Label("Pin Next Step to Lock Screen", systemImage: "pin.fill")
                    }
                    .tint(DesignSystem.accentPrimary)
                    .onChange(of: pinNowToLockScreen) { _, pinned in
                        WidgetSyncService.shared.setNowPinned(pinned)
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.accentPrimary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Home Screen Widgets")
                                .font(.system(size: 15, weight: .semibold, design: .default))
                            Text("Long-press your home screen → Edit → Add Widget → search \(UserFacingCopy.productName). Choose Next Step, Energy Pulse, or Task Glance.")
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)
                } header: {
                    Text("Widgets & Lock Screen")
                } footer: {
                    Text("The timer pins to your Lock Screen and Dynamic Island. Pin Next Step keeps your top task visible even when the app is closed.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }
                
                // Life Profile (compiled life model)
                Section {
                    LifeProfileImportView(markdown: $lifeProfileMarkdown)

                    workTimeRow(title: "Work starts", hour: $lifeProfile.workStartHour, minute: $lifeProfile.workStartMinute)
                    workTimeRow(title: "Work ends", hour: $lifeProfile.workEndHour, minute: $lifeProfile.workEndMinute)
                } header: {
                    Text("Brain context")
                } footer: {
                    Text("Import your full life profile. The brain compiles identity, time blocks, and commitments — fixed blocks appear on Timeline automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }

                // Energy Profile
                Section {
                    Picker("Best focus time", selection: $lifeProfile.focusTimePreference) {
                        ForEach(FocusTimePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    
                    HStack {
                        Text("Target Sleep")
                        Spacer()
                        Text(String(format: "%.1f hours", targetSleepHours))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    
                    Slider(value: $targetSleepHours, in: 5...10, step: 0.5)
                        .tint(DesignSystem.accentPrimary)
                } header: {
                    Text("Energy Profile")
                }
                
                // Help
                Section {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .replayAppFeatureTour, object: nil)
                        }
                    } label: {
                        Label("Replay app tour", systemImage: "map")
                    }
                    .accessibilityIdentifier("settings-replay-tour")
                } header: {
                    Text("Help")
                } footer: {
                    Text("Walk through Briefing, Today, Capture, Brain, and profile features again.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Phase 1)")
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    
                    HStack {
                        Text("AI Engine")
                        Spacer()
                        Text("GLM 5.2")
                            .foregroundColor(DesignSystem.textMuted)
                    }
                } header: {
                    Text("About \(UserFacingCopy.productName)")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .onAppear {
                apiKeysVM.refresh()
                refreshAIUsageSummary()
                lifeProfile = UserLifeProfileStore.load()
                structuredProfileSections = LifeProfileComposer.parse(lifeProfile.profileText)
                UserLifeProfileStore.syncUserNameFromProfileIfNeeded()
                if userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    userName = UserLifeProfileStore.resolvedDisplayName()
                }
            }
            .onChange(of: structuredProfileSections.personality) { _, _ in syncStructuredProfileToStore() }
            .onChange(of: structuredProfileSections.adhdFocusPatterns) { _, _ in syncStructuredProfileToStore() }
            .onChange(of: structuredProfileSections.dailySchedule) { _, _ in syncStructuredProfileToStore() }
            .onChange(of: structuredProfileSections.planningPreferences) { _, _ in syncStructuredProfileToStore() }
            .onChange(of: lifeProfile.workStartHour) { _, _ in persistLifeProfile() }
            .onChange(of: lifeProfile.workStartMinute) { _, _ in persistLifeProfile() }
            .onChange(of: lifeProfile.workEndHour) { _, _ in persistLifeProfile() }
            .onChange(of: lifeProfile.workEndMinute) { _, _ in persistLifeProfile() }
            .onChange(of: lifeProfile.focusTimePreference) { _, _ in persistLifeProfile() }
            .onChange(of: lifeProfile.profileText) { _, _ in persistLifeProfile() }
            .onChange(of: lifeProfile.fixedScheduleNotes) { _, _ in persistLifeProfile() }
            .keyboardDismissToolbar()
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("screen-settings")
    }

    private func syncStructuredProfileToStore() {
        lifeProfile.profileText = LifeProfileComposer.compile(structuredProfileSections)
        persistLifeProfile()
    }

    private var aiUsagePreviewText: String {
        if aiUsageSummary.dailyTotalTokens == 0, aiUsageSummary.dailyRequestCount == 0 {
            return "No AI usage logged today"
        }
        return "Today: \(GLMUsageSummary.formatTokenCount(aiUsageSummary.dailyTotalTokens)) tokens · \(String(format: "$%.4f", aiUsageSummary.dailyTotalUSD))"
    }

    private func refreshAIUsageSummary() {
        aiUsageSummary = GLMService.shared.usageSummary()
    }

    private func organizeLifeProfileInSettings() async {
        profileOrganizeError = nil
        let prompt = LifeProfileComposer.organizeStructuredPrompt(structuredProfileSections)
        do {
            let polished = try await GLMService.shared.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.profileOrganizeSystem,
                tier: .economy
            )
            let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            structuredProfileSections = LifeProfileComposer.parse(trimmed)
            syncStructuredProfileToStore()
            await syncTasksFromProfile(showOrganizeContext: true)
        } catch {
            structuredProfileSections = LifeProfileComposer.organizeLocally(structuredProfileSections)
            syncStructuredProfileToStore()
            profileOrganizeError = "AI unavailable (\(error.localizedDescription)) — formatted sections locally."
            await syncTasksFromProfile(showOrganizeContext: true)
        }
    }

    private func syncTasksFromProfile(showOrganizeContext: Bool = false) async {
        taskSyncMessage = nil
        isSyncingTasks = true
        defer { isSyncingTasks = false }

        let userId = FirebaseManager.shared.currentUserId
            ?? UserDefaults.standard.string(forKey: "saved_user_uid")
            ?? ""
        guard !userId.isEmpty else {
            taskSyncMessage = "Sign in to create tasks from your profile."
            return
        }

        lifeProfile = UserLifeProfileStore.load()
        await shell.refreshTasksFromProfile(userId: userId, sections: structuredProfileSections)
        await shell.tasksVM.loadTasks(userId: userId)

        lifeProfile = UserLifeProfileStore.load()
        structuredProfileSections = LifeProfileComposer.parse(lifeProfile.profileText)

        let onboardingCount = shell.tasksVM.tasks.filter { $0.tags.contains("onboarding") }.count
        if onboardingCount > 0 {
            taskSyncMessage = "Created \(onboardingCount) task\(onboardingCount == 1 ? "" : "s") from your profile."
        } else if showOrganizeContext {
            taskSyncMessage = "Profile updated. Add fixed timings like \"Daily standup 10:00 AM\" below, then tap Create tasks again."
        } else {
            taskSyncMessage = "No fixed timings found. Add entries like \"Daily standup 10:00 AM\" in Fixed timings."
        }
    }

    private func workTimeRow(title: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        let binding = Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: hour.wrappedValue, minute: minute.wrappedValue, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                hour.wrappedValue = Calendar.current.component(.hour, from: newDate)
                minute.wrappedValue = Calendar.current.component(.minute, from: newDate)
            }
        )
        return HStack {
            Text(title)
            Spacer()
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private func persistLifeProfile() {
        let startMins = lifeProfile.workStartHour * 60 + lifeProfile.workStartMinute
        let endMins = lifeProfile.workEndHour * 60 + lifeProfile.workEndMinute
        if endMins <= startMins {
            lifeProfile.workEndHour = min(lifeProfile.workStartHour + 8, 23)
            lifeProfile.workEndMinute = lifeProfile.workStartMinute
        }
        lifeProfile.peakStartHour = lifeProfile.focusTimePreference.peakStartHour
        lifeProfile.peakEndHour = lifeProfile.focusTimePreference.peakEndHour
        UserLifeProfileStore.save(lifeProfile)
    }

    private func refreshAfterHealthSync(userId: String) async {
        guard !userId.isEmpty, healthSync.syncPhase == .complete else { return }
        await shell.refreshContext(
            userId: userId,
            userName: UserLifeProfileStore.resolvedDisplayName(),
            peakStartHour: UserLifeProfileStore.load().peakStartHour
        )
        shell.refreshWidgetData()
    }
}
