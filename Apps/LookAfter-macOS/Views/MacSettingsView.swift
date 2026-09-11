import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData

/// macOS settings — account, license, and profile.
struct MacSettingsView: View {
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("targetSleepHours") private var targetSleepHours: Double = 8.0
    @AppStorage(ADHDFocusChallenge.storageKey) private var adhdFocusChallengeRaw = ADHDFocusChallenge.taskInitiation.rawValue
    @AppStorage("aiCoachTone") private var aiCoachTone: String = "Encouraging & Gentle"
    @AppStorage("userKeyGoals") private var userKeyGoals: String = ""
    @AppStorage("appCurrencySymbol") private var appCurrencySymbol: String = "₹"
    @AppStorage("focusDurationMinutes") private var focusDurationMinutes: Int = 25

    @State private var lifeProfile = UserLifeProfileStore.load()

    private let focusChallenges = ADHDFocusChallenge.allCases

    private let coachTones = [
        "Encouraging & Gentle",
        "Direct & Action-Oriented",
        "Gamified & Energetic",
        "Socratic & Reflective"
    ]

    var body: some View {
        ZStack {
            PremiumBackground()

            PremiumForm {
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
                                Text("Cloud sync active")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(DesignSystem.contentSurface)

                    Button(role: .destructive, action: {
                        try? FirebaseManager.shared.signOut()
                    }) {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }
                    .listRowBackground(DesignSystem.contentSurface)
                }, header: {
                    Text("Account")
                })

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
                        TextField("Goals", text: $userKeyGoals)
                            .font(.system(size: 14, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }, header: {
                    Text("Personal Profile")
                })

                Section(content: {
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
                    .listRowBackground(DesignSystem.contentSurface)

                    NavigationLink(destination: {
                        APIKeysSettingsView()
                    }, label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("API Keys", systemImage: "key.fill")
                            Text(GLMService.shared.hasConfiguredAPIKey
                                 ? "Direct z.ai GLM key configured"
                                 : "Add a GLM API key to enable AI")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    })
                    .listRowBackground(DesignSystem.contentSurface)

                    NavigationLink(destination: {
                        LicenseSettingsView()
                    }, label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("License", systemImage: "checkmark.seal.fill")
                            Text(LicenseManager.shared.isLicensed ? "Product key active (cloud voice)" : "Optional — cloud voice / legacy proxy")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    })
                    .listRowBackground(DesignSystem.contentSurface)

                    NavigationLink(destination: {
                        GLMConfigurationSettingsView()
                    }, label: {
                        Label("GLM Configuration", systemImage: "cpu")
                    })
                    .listRowBackground(DesignSystem.contentSurface)
                }, header: {
                    Text("AI Engine")
                }, footer: {
                    Text(GLMService.shared.hasConfiguredAPIKey
                         ? "AI calls z.ai directly with your GLM API key."
                         : "Add a GLM API key in API Keys to enable AI.")
                })

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

                    Stepper(
                        "Target sleep: \(String(format: "%.1f", targetSleepHours))h",
                        value: $targetSleepHours,
                        in: 4...12,
                        step: 0.5
                    )
                }, header: {
                    Text("Preferences")
                })
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
    }
}
