import SwiftUI
import LifeOSCore
import LifeOSAI
import LifeOSData

/// macOS settings — account, AI keys, and profile without iOS shell dependencies.
struct MacSettingsView: View {
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("targetSleepHours") private var targetSleepHours: Double = 8.0
    @AppStorage("adhdFocusChallenge") private var adhdFocusChallenge: String = "Task Initiation"
    @AppStorage("aiCoachTone") private var aiCoachTone: String = "Encouraging & Gentle"
    @AppStorage("userKeyGoals") private var userKeyGoals: String = ""
    @AppStorage("appCurrencySymbol") private var appCurrencySymbol: String = "₹"
    @AppStorage("focusDurationMinutes") private var focusDurationMinutes: Int = 25

    @State private var lifeProfile = UserLifeProfileStore.load()
    @StateObject private var apiKeysVM = APIKeysSettingsViewModel()

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
        ZStack {
            PremiumBackground()

            PremiumForm {
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
                                Text("Cloud sync active")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(DesignSystem.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    Button(role: .destructive, action: {
                        try? FirebaseManager.shared.signOut()
                    }) {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                } header: {
                    Text("Account")
                }

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

                    TextField("Current goals & focus areas", text: $userKeyGoals, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Personal Profile")
                }

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
                    .listRowBackground(Color.white.opacity(0.05))

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
                        .listRowBackground(Color.white.opacity(0.05))
                    }

                    NavigationLink {
                        GLMConfigurationSettingsView()
                    } label: {
                        Label("GLM Configuration", systemImage: "cpu")
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    NavigationLink {
                        APIKeysSettingsView()
                    } label: {
                        Label("Manage API Keys", systemImage: "key.fill")
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                } header: {
                    Text("AI Engine")
                }

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

                    Stepper(
                        "Target sleep: \(String(format: "%.1f", targetSleepHours))h",
                        value: $targetSleepHours,
                        in: 4...12,
                        step: 0.5
                    )
                } header: {
                    Text("Preferences")
                }

                Section {
                    Picker("Gender", selection: Binding(
                        get: { lifeProfile.gender ?? .preferNotToSay },
                        set: { newGender in
                            lifeProfile.gender = newGender
                            UserLifeProfileStore.save(lifeProfile)
                        }
                    )) {
                        ForEach(UserGender.allCases) { gender in
                            Text(gender.label).tag(gender)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                } header: {
                    Text("Profile")
                }
            }
        }
        .navigationTitle("Settings")
    }
}
