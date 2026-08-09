import SwiftUI
import AVFoundation
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterHealth
import LookAfterFeatures

/// Settings View — health tracking, ADHD features, license, and profile.
struct SettingsView: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss

    @AppStorage("enableHealth") private var enableHealth: Bool = true
    @AppStorage("gmail_integration_enabled") private var gmailIntegrationEnabled: Bool = false
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
    @AppStorage(ADHDFocusChallenge.storageKey) private var adhdFocusChallengeRaw = ADHDFocusChallenge.taskInitiation.rawValue
    @AppStorage("aiCoachTone") private var aiCoachTone: String = "Encouraging & Gentle"
    @AppStorage("userKeyGoals") private var userKeyGoals: String = ""
    @AppStorage("appCurrencySymbol") private var appCurrencySymbol: String = "₹"
    @AppStorage("focusDurationMinutes") private var focusDurationMinutes: Int = 25
    @AppStorage("pinNowToLockScreen") private var pinNowToLockScreen = false
    @State private var pinNowStatusMessage: String?
    @State private var isPinningNow = false
    @AppStorage(FlowDirectorFeature.userDefaultsKey) private var enableFlowDirector = false
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRaw = AppAppearanceMode.system.rawValue
    @AppStorage(SpeechVoiceSettings.providerKey) private var speechProviderRaw = SpeechVoiceProvider.appleEnhanced.rawValue
    @AppStorage(SpeechVoiceSettings.voiceIdentifierKey) private var speechVoiceIdentifier = ""
    @AppStorage(SpeechVoiceSettings.rateKey) private var speechRate = 0.48
    @AppStorage(SpeechVoiceSettings.pitchKey) private var speechPitch = 1.0
    @AppStorage(SpeechVoiceSettings.autoSpeakRepliesKey) private var autoSpeakReplies = true
    @AppStorage(SpeechVoiceSettings.autoSpeakProactiveKey) private var autoSpeakProactive = false
    @AppStorage(SpeechVoiceSettings.spokenStyleKey) private var preferSpokenStyle = true
    @AppStorage("lookafter.accountability.enabled") private var accountabilityEnabled = false
    @AppStorage(AccountabilitySettings.contactNameKey) private var accountabilityContactName = ""
    @AppStorage(SpeechVoiceSettings.cloudVoiceKey) private var cloudVoice = "nova"
    @StateObject private var speechPreview = PlanningSpeechSynthesizer()
    @StateObject private var notificationPermission = NotificationPermissionService.shared
    @State private var notificationPreferences = NotificationPreferencesStore.load()

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
    @State private var aiUsageSummary = GLMUsageSummary()
    @State private var showHealthVerification = false
    
    private let focusChallenges = ADHDFocusChallenge.allCases
    
    private let coachTones = [
        "Encouraging & Gentle",
        "Direct & Action-Oriented",
        "Gamified & Energetic",
        "Socratic & Reflective"
    ]
    
    var body: some View {
        PremiumForm {
                // Account & Cloud Sync
                Section(content: {
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
                }, header: {
                    Text("Account & Cloud Sync")
                }, footer: {
                    Text("Leave blank to use the name from your Life Profile (e.g. \"I'm Alex…\").")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                Section(content: {
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
                }, header: {
                    Text("Display")
                }, footer: {
                    Text(appearance.usesSystemSetting
                         ? "Look After follows your iPhone light or dark setting."
                         : "Dark Mode is controlled inside the app. Turn off “Match iPhone appearance” to change it here.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                Section(content: {
                    Toggle(isOn: Binding(
                        get: { notificationPreferences.globallyEnabled },
                        set: { enabled in
                            notificationPreferences.globallyEnabled = enabled
                            NotificationPreferencesStore.save(notificationPreferences)
                            if enabled {
                                Task { _ = await notificationPermission.requestAuthorization() }
                            }
                            Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
                        }
                    )) {
                        Label("Proactive reminders", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("settings-notifications-master-toggle")
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    if notificationPreferences.globallyEnabled {
                        ForEach(NotificationKind.allCases.filter(\.countsTowardDailyCap)) { kind in
                            Toggle(isOn: Binding(
                                get: { notificationPreferences.isEnabled(kind) },
                                set: { enabled in
                                    notificationPreferences.setEnabled(kind, enabled)
                                    NotificationPreferencesStore.save(notificationPreferences)
                                    Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
                                }
                            )) {
                                Text(kind.displayName)
                            }
                            .accessibilityIdentifier("settings-notifications-\(kind.rawValue)-toggle")
                            .listRowBackground(DesignSystem.backgroundSecondary)
                        }

                        Toggle(isOn: Binding(
                            get: { notificationPreferences.isEnabled(.focusBreak) },
                            set: { enabled in
                                notificationPreferences.setEnabled(.focusBreak, enabled)
                                NotificationPreferencesStore.save(notificationPreferences)
                                Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
                            }
                        )) {
                            Text(NotificationKind.focusBreak.displayName)
                        }
                        .accessibilityIdentifier("settings-notifications-focusBreak-toggle")
                        .listRowBackground(DesignSystem.backgroundSecondary)
                    }

                    if notificationPermission.isDenied {
                        Button(action: {
                            notificationPermission.openSystemSettings()
                        }, label: {
                            Label("Open iOS Settings", systemImage: "gear")
                        })
                        .accessibilityIdentifier("settings-notifications-open-system-settings")
                        .listRowBackground(DesignSystem.backgroundSecondary)
                    }
                }, header: {
                    Text("Notifications")
                }, footer: {
                    Text(notificationPermission.isDenied
                         ? "Notifications are off in iOS Settings. Look After works fully without them — you won't get proactive reminders."
                         : "Up to 2 calm proactive reminders per day. Focus break alerts only fire during an active focus session.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                Section(content: {
                    Toggle("Accountability nudges", isOn: $accountabilityEnabled)
                    TextField("Contact name", text: $accountabilityContactName)
                        .textInputAutocapitalization(.words)
                }, header: {
                    Text("Accountability")
                }, footer: {
                    Text("Optional local reminder to ping someone when a micro-start window opens. Share sheet only — no SMS from the app.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                Section(content: {
                    Button(action: startAppTour) {
                        Label("Start tour", systemImage: "map")
                    }
                    .accessibilityIdentifier("settings-start-tour")
                    .listRowBackground(DesignSystem.backgroundSecondary)
                }, header: {
                    Text("Help")
                }, footer: {
                    Text("Walk through Briefing, Today, Review, Capture, Brain, and You — useful if you started before the tour existed or want a refresher.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                Section(content: {
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
                }, header: {
                    Text("Profile")
                }, footer: {
                    Text("Cycle tracking is available when you identify as female.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                // AI Executive Profile & Personalization
                Section(content: {
                    Picker("Primary Focus Challenge", selection: $adhdFocusChallengeRaw) {
                        ForEach(focusChallenges) { challenge in
                            Text(challenge.label).tag(challenge.rawValue)
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
                }, header: {
                    Text("Personal Profile")
                }, footer: {
                    Text("This profile helps daily planning, task micro-steps, and chat adapt to your unique brain.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                // Voice & Speech
                Section(content: {
                    Picker("Voice engine", selection: $speechProviderRaw) {
                        ForEach(SpeechVoiceProvider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .onChange(of: speechProviderRaw) { _, _ in
                        SpeechVoiceSettings.provider = SpeechVoiceProvider(rawValue: speechProviderRaw) ?? .appleEnhanced
                    }

                    if speechProviderRaw == SpeechVoiceProvider.cloud.rawValue {
                        Picker("Cloud voice", selection: $cloudVoice) {
                            ForEach(SpeechVoiceSettings.cloudVoices, id: \.id) { voice in
                                Text(voice.label).tag(voice.id)
                            }
                        }

                        if !LicenseManager.shared.isLicensed {
                            Text("Activate your product key in Settings → License to use cloud voice.")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.warning)
                        }
                    } else {
                        Picker("Voice", selection: $speechVoiceIdentifier) {
                            Text("Automatic (best available)").tag("")
                            ForEach(PlanningSpeechSynthesizer.availableEnglishVoices(), id: \.identifier) { voice in
                                Text(voicePickerLabel(voice)).tag(voice.identifier)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Speaking rate")
                            Spacer()
                            Text(speechRateLabel)
                                .foregroundColor(DesignSystem.textSecondary)
                                .font(.system(size: 13))
                        }
                        Slider(value: $speechRate, in: 0.35...0.65, step: 0.01)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Pitch")
                            Spacer()
                            Text(String(format: "%.2f", speechPitch))
                                .foregroundColor(DesignSystem.textSecondary)
                                .font(.system(size: 13))
                        }
                        Slider(value: $speechPitch, in: 0.75...1.25, step: 0.01)
                    }

                    Toggle("Auto-speak AI replies", isOn: $autoSpeakReplies)
                    Toggle("Auto-speak proactive alerts", isOn: $autoSpeakProactive)
                    Toggle("Write replies for speech", isOn: $preferSpokenStyle)

                    Button {
                        HapticManager.impact(.light)
                        speechPreview.previewSample()
                    } label: {
                        Label(
                            speechPreview.isSpeaking ? "Speaking…" : "Preview voice",
                            systemImage: speechPreview.isSpeaking ? "speaker.wave.2.fill" : "play.circle.fill"
                        )
                    }
                    .disabled(speechPreview.isSpeaking)

                    if !speechPreview.activeVoiceName.isEmpty {
                        Text("Active: \(speechPreview.activeVoiceName)")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }, header: {
                    Text("Voice & Speech")
                }, footer: {
                    if speechProviderRaw == SpeechVoiceProvider.cloud.rawValue {
                        Text("Cloud voice uses OpenAI neural TTS through the licensed secure proxy — no API keys on your device.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    } else {
                        Text("Voice quality improves automatically when Enhanced or Premium English voices are available on this device.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                })

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

                    Toggle(isOn: $gmailIntegrationEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Gmail triage", systemImage: "envelope.badge")
                            Text("Read unread mail for AI triage and travel alerts")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                    .onChange(of: gmailIntegrationEnabled) { _, enabled in
                        GmailIntegrationSettings.isEnabled = enabled
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    NavigationLink(destination: {
                        LicenseSettingsView()
                    }, label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("License", systemImage: "checkmark.seal.fill")
                            Text(LicenseManager.shared.isLicensed ? "Licensed AI via secure proxy" : "Enter product key to unlock AI")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    })
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    NavigationLink(destination: {
                        GLMUsageSettingsView()
                    }, label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("AI Usage", systemImage: "chart.bar.doc.horizontal")
                            Text(aiUsagePreviewText)
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    })
                    .listRowBackground(DesignSystem.backgroundSecondary)
                    .accessibilityIdentifier("settings-ai-usage")

                    NavigationLink(destination: {
                        GLMConfigurationSettingsView()
                    }, label: {
                        Label("GLM Configuration", systemImage: "cpu")
                    })
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    Text(LicenseManager.shared.isLicensed
                         ? "All AI runs through the secure proxy. Keys never leave the server."
                         : "Redeem a product key to unlock AI and cloud voice.")
                        .font(.system(size: 12, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                        .listRowBackground(DesignSystem.backgroundSecondary)

                    Toggle(isOn: Binding(
                        get: { TaskManagementPreferences.highQualitySchedulingEnabled },
                        set: { TaskManagementPreferences.highQualitySchedulingEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("High-quality scheduling")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Uses GLM 5.2 (premium tier) for Adjust schedule previews.")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)

                    Toggle(isOn: Binding(
                        get: { TaskManagementPreferences.smarterFocusTipsEnabled },
                        set: { TaskManagementPreferences.smarterFocusTipsEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smarter focus tips")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Optional AI refinement on All Tasks duration labels.")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }
                    .listRowBackground(DesignSystem.backgroundSecondary)
                } header: {
                    Text("AI Engine")
                } footer: {
                    Text("Premium = \(GLMService.shared.configuration.defaultModel). Standard = \(GLMService.shared.configuration.standardModel). Economy = \(GLMService.shared.configuration.economyModel).")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }
                
                // Preferences & Currency
                Section(content: {
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
                }, header: {
                    Text("Preferences")
                })
                
                // Features
                Section(content: {
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
                }, header: {
                    Text("Features")
                }, footer: {
                    if enableFlowDirector {
                        Text("Picks your next task from calendar, energy, and deadlines — without generic category labels.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                })
                
                if enableHealth {
                    Section(content: {
                        if let status = healthSync.connectionStatus {
                            HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                                Image(systemName: settingsStatusIcon(status.kind))
                                    .font(.system(size: 22))
                                    .foregroundColor(settingsStatusColor(status.kind))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(status.headline)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(DesignSystem.textPrimary)
                                    Text(status.explanation)
                                        .font(.system(size: 12))
                                        .foregroundColor(DesignSystem.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .listRowBackground(DesignSystem.backgroundSecondary)
                            .accessibilityIdentifier("settings-health-status-row")

                            if status.needsAttention {
                                Button(action: { showHealthVerification = true }) {
                                    Label("What's wrong?", systemImage: "questionmark.circle")
                                }
                                .listRowBackground(DesignSystem.backgroundSecondary)
                            }
                        }

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

                        Button(action: openHealthApp) {
                            Label("Open Health app", systemImage: "heart.text.square.fill")
                        }
                        .listRowBackground(DesignSystem.backgroundSecondary)

                        NavigationLink(destination: {
                            HealthTroubleshootingView(
                                healthSync: healthSync,
                                userId: FirebaseManager.shared.resolvedUserId
                            )
                            .environmentObject(shell)
                        }, label: {
                            Label("Help with Watch data", systemImage: "lifepreserver")
                        })
                        .listRowBackground(DesignSystem.backgroundSecondary)
                    }, header: {
                        Text("Health Data Sync")
                    }, footer: {
                        Text("\(UserFacingCopy.productName) reads from the iPhone Health app, which includes metrics recorded by your Apple Watch.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.textMuted)
                    })
                }

                if lifeProfile.gender == .female {
                Section(content: {
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
                        NavigationLink(destination: {
                            CycleDashboardView()
                        }, label: {
                            Label("Cycle dashboard", systemImage: "calendar.circle")
                        })
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
                }, header: {
                    Text("Cycle tracking")
                }, footer: {
                    Text("Optional. Includes menstrual data from Apple Health when enabled. \(UserFacingCopy.medicalDisclaimer)")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })
                }
                
                Section(content: {
                    Toggle(isOn: $pinNowToLockScreen) {
                        Label("Pin Next Step to Lock Screen", systemImage: "pin.fill")
                    }
                    .tint(DesignSystem.accentPrimary)
                    .disabled(isPinningNow)
                    .onChange(of: pinNowToLockScreen) { _, pinned in
                        Task {
                            isPinningNow = true
                            defer { isPinningNow = false }
                            let result = await WidgetSyncService.shared.setNowPinned(pinned, shell: shell)
                            pinNowStatusMessage = result.message
                            if pinned, !result.success {
                                pinNowToLockScreen = false
                            }
                        }
                    }

                    if isPinningNow {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Starting Live Activity…")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    } else if let pinNowStatusMessage {
                        Text(pinNowStatusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(pinNowStatusMessage.contains("Could not") || pinNowStatusMessage.contains("No next")
                                ? Color.orange
                                : DesignSystem.textMuted)
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
                }, header: {
                    Text("Widgets & Lock Screen")
                }, footer: {
                    Text("The timer pins to your Lock Screen and Dynamic Island. Pin Next Step keeps your top task visible even when the app is closed.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })
                
                // Life Profile (compiled life model)
                Section(content: {
                    LifeProfileImportView(markdown: $lifeProfileMarkdown)

                    workTimeRow(title: "Work starts", hour: $lifeProfile.workStartHour, minute: $lifeProfile.workStartMinute)
                    workTimeRow(title: "Work ends", hour: $lifeProfile.workEndHour, minute: $lifeProfile.workEndMinute)
                }, header: {
                    Text("Brain context")
                }, footer: {
                    Text("Import your full life profile. The brain compiles identity, time blocks, and commitments — fixed blocks appear on Timeline automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                })

                // Energy Profile
                Section(content: {
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
                }, header: {
                    Text("Energy Profile")
                })

                // About
                Section(content: {
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
                }, header: {
                    Text("About \(UserFacingCopy.productName)")
                })
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .onAppear {
                refreshAIUsageSummary()
                lifeProfile = UserLifeProfileStore.load()
                notificationPreferences = NotificationPreferencesStore.load()
                structuredProfileSections = LifeProfileComposer.parse(lifeProfile.profileText)
                UserLifeProfileStore.syncUserNameFromProfileIfNeeded()
                if userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    userName = UserLifeProfileStore.resolvedDisplayName()
                }
                adhdFocusChallengeRaw = ADHDFocusChallenge.normalizeStorage().rawValue
                Task { await notificationPermission.refreshStatus() }
                let userId = FirebaseManager.shared.resolvedUserId
                healthSync.refreshConnectionStatus(userId: userId, healthSummary: shell.brainVM.healthSummary)
            }
            .sheet(isPresented: $showHealthVerification) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: DesignSystem.spacingMD) {
                            if let status = healthSync.connectionStatus {
                                HealthStatusBanner(
                                    status: status,
                                    style: .full,
                                    onPrimaryAction: {
                                        HealthStatusActionHandler.perform(
                                            status.primaryAction,
                                            onConnect: { showHealthVerification = false },
                                            onSync: {
                                                Task {
                                                    let userId = FirebaseManager.shared.resolvedUserId
                                                    await healthSync.syncHealthData(userId: userId)
                                                    await refreshAfterHealthSync(userId: userId)
                                                }
                                            },
                                            onOpenSettings: { }
                                        )
                                    }
                                )
                            }
                            if let report = healthSync.verificationReport {
                                HealthVerificationReportView(report: report)
                            }
                        }
                        .padding(DesignSystem.spacingLG)
                    }
                    .background(DesignSystem.backgroundPrimary.ignoresSafeArea())
                    .navigationTitle("What's wrong?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showHealthVerification = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
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

    private var speechRateLabel: String {
        if speechRate < 0.42 { return "Slower" }
        if speechRate > 0.55 { return "Faster" }
        return "Natural"
    }

    private func voicePickerLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        var quality = ""
        if #available(iOS 16.0, *) {
            switch voice.quality {
            case .premium: quality = " · Premium"
            case .enhanced: quality = " · Enhanced"
            default: break
            }
        }
        return "\(voice.name) (\(voice.language))\(quality)"
    }

    private func refreshAIUsageSummary() {
        aiUsageSummary = GLMService.shared.usageSummary()
    }

    private func startAppTour() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .replayAppFeatureTour, object: nil)
        }
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
        healthSync.refreshConnectionStatus(userId: userId, healthSummary: shell.brainVM.healthSummary)
        await shell.refreshContext(
            userId: userId,
            userName: UserLifeProfileStore.resolvedDisplayName(),
            peakStartHour: UserLifeProfileStore.load().peakStartHour
        )
        shell.refreshWidgetData()
    }

    private func openHealthApp() {
        if let url = HealthAppLinks.healthAppURL {
            UIApplication.shared.open(url)
        }
    }

    private func settingsStatusIcon(_ kind: HealthConnectionKind) -> String {
        switch kind {
        case .allGood: return "checkmark.circle.fill"
        case .partialData, .syncStale, .waitingForData: return "exclamationmark.triangle.fill"
        case .accessBlocked, .trackingOff, .notSetUp: return "xmark.circle.fill"
        }
    }

    private func settingsStatusColor(_ kind: HealthConnectionKind) -> Color {
        switch kind {
        case .allGood: return DesignSystem.success
        case .partialData, .syncStale, .waitingForData: return DesignSystem.warning
        case .accessBlocked, .trackingOff, .notSetUp: return DesignSystem.error
        }
    }
}
