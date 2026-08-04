import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterHealth
import LookAfterFeatures

/// First-run setup — asks every detail explicitly instead of inferring from prose.
struct OnboardingView: View {
    let userId: String
    @ObservedObject var healthSync: HealthSyncService
    @EnvironmentObject private var shell: AppShellState
    let onComplete: (_ sections: StructuredLifeProfileSections?) -> Void

    @State private var step: StartStep = .welcome
    @State private var userName = ""
    @State private var selectedGender: UserGender?
    @State private var structuredSections = StructuredLifeProfileSections()
    @State private var fixedScheduleNotes = ""
    @State private var workStartTime = Self.defaultWorkStart
    @State private var workEndTime = Self.defaultWorkEnd
    @State private var focusPreference: FocusTimePreference = .notSure
    @State private var targetSleepHours: Double = 8.0
    @State private var adhdFocusChallenge = "Task initiation"
    @State private var userKeyGoals = ""
    @State private var enableHealth = true
    @State private var trackCycle = false
    @State private var cycleLengthDays = 28
    @State private var periodLengthDays = 5
    @State private var lastPeriodStart = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    @State private var selectedCycleSymptoms: Set<String> = []
    @State private var healthConnectError: String?
    @State private var healthSkipped = false
    @State private var showHealthConnectSheet = false
    @State private var isOrganizing = false
    @State private var organizeError: String?
    @State private var lifeProfileMarkdown = ""

    private var aiAvailable: Bool { GLMService.shared.hasConfiguredAPIKey }

    private let adhdChallenges = [
        "Task initiation",
        "Time blindness",
        "Hyperfocus",
        "Overwhelm",
        "Working memory",
        "Emotional regulation"
    ]

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                if step != .welcome {
                    progressHeader
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                        stepHeader
                        stepContent
                        footerActions
                    }
                    .padding(.horizontal, DesignSystem.spacingLG)
                    .padding(.vertical, 28)
                }
            }
        }
        .keyboardDismissToolbar()
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("screen-onboarding")
        .onAppear(perform: prefillFromExisting)
    }

    // MARK: - Progress

    private var progressHeader: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.backgroundElevated)
                        .frame(height: 4)
                    Capsule()
                        .fill(DesignSystem.accentPrimary)
                        .frame(width: geo.size.width * step.progress, height: 4)
                        .animation(.easeInOut(duration: 0.25), value: step)
                }
            }
            .frame(height: 4)

            Text("Step \(step.index) of \(StartStep.questionCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DesignSystem.textMuted)
        }
        .padding(.horizontal, DesignSystem.spacingLG)
        .padding(.top, 12)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)
            Text(step.subtitle)
                .font(.system(size: 15))
                .foregroundColor(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .name:
            nameStep
        case .gender:
            genderStep
        case .schedule:
            scheduleStep
        case .commitments:
            commitmentsStep
        case .profile:
            profileStep
        case .health:
            healthStep
        case .cycle:
            cycleStep
        case .notifications:
            notificationsStep
        case .ready:
            readyStep
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            checklistRow(icon: "person.fill", title: "Your name & identity", detail: "So we greet you and personalize features")
            checklistRow(icon: "clock.fill", title: "Work hours & energy", detail: "When you work and focus best")
            checklistRow(icon: "calendar", title: "Fixed commitments", detail: "Standup, gym — never moved by AI")
            checklistRow(icon: "brain.head.profile", title: "How your brain works", detail: "ADHD patterns & planning rules")
            checklistRow(icon: "heart.fill", title: "Apple Health", detail: "Sleep & recovery for smarter planning")
            Text("Takes about 3 minutes. Everything can be changed in Settings later.")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.textMuted)
                .padding(.top, 4)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("First name", text: $userName)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.backgroundElevated))
                .foregroundColor(DesignSystem.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("What’s hardest right now?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                Picker("Focus challenge", selection: $adhdFocusChallenge) {
                    ForEach(adhdChallenges, id: \.self) { challenge in
                        Text(challenge).tag(challenge)
                    }
                }
                .pickerStyle(.menu)
                .tint(DesignSystem.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("One goal for this week (optional)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                TextField("e.g. Finish project proposal", text: $userKeyGoals)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.backgroundElevated))
                    .foregroundColor(DesignSystem.textPrimary)
            }
        }
    }

    private var genderStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How do you identify?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.textSecondary)

            VStack(spacing: 10) {
                ForEach(UserGender.allCases) { gender in
                    Button {
                        selectedGender = gender
                        if gender != .female {
                            trackCycle = false
                        }
                    } label: {
                        HStack {
                            Text(gender.label)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(DesignSystem.textPrimary)
                            Spacer()
                            if selectedGender == gender {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.accentPrimary)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedGender == gender
                                      ? DesignSystem.accentPrimary.opacity(0.15)
                                      : DesignSystem.backgroundElevated)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Used to personalize features like cycle tracking. You can change this anytime in Settings.")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.textMuted)
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            timePicker(title: "Work starts", selection: $workStartTime)
            timePicker(title: "Work ends", selection: $workEndTime)

            VStack(alignment: .leading, spacing: 8) {
                Text("When do you focus best?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                Picker("Focus time", selection: $focusPreference) {
                    ForEach(FocusTimePreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .pickerStyle(.menu)
                .tint(DesignSystem.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Target sleep")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f hours", targetSleepHours))
                        .foregroundColor(DesignSystem.textMuted)
                }
                Slider(value: $targetSleepHours, in: 5...10, step: 0.5)
                    .tint(DesignSystem.accentPrimary)
            }
        }
    }

    private var commitmentsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("List anything at a fixed time — the planner will never move these.")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textMuted)

            TextField("Daily standup 10:00 AM, Gym 7 PM", text: $fixedScheduleNotes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.backgroundElevated))
                .foregroundColor(DesignSystem.textPrimary)

            Text("One per line or separated by commas. We’ll turn these into tasks when you finish.")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.textMuted)

            if fixedScheduleNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No fixed commitments? You can skip — add them later in Settings.")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste your life profile — who you are, your mission, schedule, and what matters most. The brain uses this to run your day.")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textSecondary)

            Text("Optional — paste a full profile or tap Load example. You can also skip and let the brain learn from your schedule and daily reflection.")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.textMuted)

            LifeProfileImportView(markdown: $lifeProfileMarkdown)
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $enableHealth) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use Apple Health")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                    Text("Sleep, HRV, steps, and heart rate improve capacity and recovery insights.")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            .tint(DesignSystem.accentPrimary)
            .onChange(of: enableHealth) { _, enabled in
                UserDefaults.standard.set(enabled, forKey: "enableHealth")
                if !enabled {
                    healthConnectError = nil
                }
            }

            if enableHealth {
                if healthSync.isAvailable {
                    Button {
                        beginHealthConnect()
                    } label: {
                        HStack {
                            Image(systemName: "heart.text.square.fill")
                            Text(healthConnectButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(DesignSystem.backgroundElevated))
                    }
                    .buttonStyle(.plain)

                    if healthSync.syncPhase == .complete {
                        Label("Connected — sleep and activity will personalize your plan.", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.success)
                    }

                    if let healthConnectError {
                        Text(healthConnectError)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("HealthKit is not available on this device.")
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }

            if healthSkipped {
                Text("You can connect Health anytime in Settings → Health Tracking.")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.accentPrimary)
            }

            Toggle(isOn: $trackCycle) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Track menstrual cycle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                    Text("Optional — phase-aware insights and logging.")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            .tint(DesignSystem.accentPrimary)
            .disabled(selectedGender != .female)
            .opacity(selectedGender == .female ? 1 : 0.45)

            if selectedGender != .female {
                Text("Cycle tracking is available when you identify as female.")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .sheet(isPresented: $showHealthConnectSheet) {
            HealthConnectSheet(healthSync: healthSync, userId: resolvedUserId())
                .environmentObject(shell)
        }
    }

    private var cycleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !trackCycle {
                Text("Cycle tracking is off. You can enable it anytime in Settings.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.textMuted)
            } else {
                DatePicker("Last period start", selection: $lastPeriodStart, displayedComponents: .date)

                Stepper("Cycle length: \(cycleLengthDays) days", value: $cycleLengthDays, in: 21...40)
                Stepper("Period length: \(periodLengthDays) days", value: $periodLengthDays, in: 2...10)

                Text("Common symptoms (optional)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)

                FlowLayout(spacing: 8) {
                    ForEach(CycleSymptomCatalog.common, id: \.self) { symptom in
                        Button {
                            if selectedCycleSymptoms.contains(symptom) {
                                selectedCycleSymptoms.remove(symptom)
                            } else {
                                selectedCycleSymptoms.insert(symptom)
                            }
                        } label: {
                            Text(symptom)
                                .font(.system(size: 12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(selectedCycleSymptoms.contains(symptom) ? DesignSystem.accentPrimary.opacity(0.2) : DesignSystem.backgroundElevated)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(UserFacingCopy.medicalDisclaimerWithProvider)
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
    }

    private func beginHealthConnect() {
        let resolvedId = resolvedUserId()
        guard !resolvedId.isEmpty else {
            healthConnectError = "Sign in first — Health sync needs your account."
            return
        }
        guard enableHealth else { return }
        healthConnectError = nil
        healthSkipped = false
        UserDefaults.standard.set(true, forKey: "enableHealth")
        showHealthConnectSheet = true
    }

    private var healthConnectButtonTitle: String {
        if healthSync.syncPhase == .complete { return "Reconnect Apple Health" }
        if healthSync.syncPhase == .failed { return "Retry Apple Health" }
        return "Connect Apple Health"
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            checklistRow(
                icon: "bell.badge",
                title: "Calm, capped reminders",
                detail: "At most 2 proactive nudges per day — meds, meetings, tasks, and your morning briefing."
            )
            checklistRow(
                icon: "hand.raised",
                title: "You're in control",
                detail: "Turn categories off anytime in Settings. Focus break alerts only run during a session."
            )
            Text("You can skip this and enable notifications later in Settings.")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.textMuted)
        }
        .accessibilityIdentifier("onboarding-notifications-step")
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow("Name", value: userName.trimmingCharacters(in: .whitespacesAndNewlines))
            if let selectedGender {
                summaryRow("Identity", value: selectedGender.label)
            }
            summaryRow("Work hours", value: workHoursLabel)
            summaryRow("Focus", value: focusPreference.label)
            summaryRow("Sleep target", value: String(format: "%.1f hours", targetSleepHours))
            if !fixedScheduleNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summaryRow("Fixed timings", value: fixedScheduleNotes)
            }
            summaryRow("Health", value: healthSummaryLabel)
            summaryRow("Profile", value: structuredSections.hasContent ? "Saved" : "Minimal")

            Text("Tap Start planning — we’ll create your first tasks and open Today.")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textMuted)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(DesignSystem.backgroundElevated))
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") { goBack() }
                    .foregroundColor(DesignSystem.textSecondary)
            }

            Spacer()

            if step == .welcome {
                Button("Get started") { step = .name }
                    .buttonStyle(.borderedProminent)
            } else if step == .health {
                Button("Skip for now") {
                    healthSkipped = true
                    trackCycle = false
                    step = .notifications
                }
                .foregroundColor(DesignSystem.textSecondary)

                Button("Continue") { goForward() }
                    .buttonStyle(.borderedProminent)
            } else if step == .notifications {
                Button("Skip for now") { step = .ready }
                    .foregroundColor(DesignSystem.textSecondary)

                Button("Enable notifications") {
                    Task {
                        _ = await NotificationPermissionService.shared.requestAuthorization()
                        step = .ready
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding-enable-notifications")
            } else if step == .ready {
                Button("Start planning") { saveAndFinish() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") { goForward() }
                    .disabled(!canContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Navigation

    private var canContinue: Bool {
        switch step {
        case .name:
            return userName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case .gender:
            return selectedGender != nil
        case .profile:
            return true
        case .cycle:
            return true
        default:
            return true
        }
    }

    private func goForward() {
        switch step {
        case .name:
            persistName()
            step = .gender
        case .gender:
            step = .schedule
        case .schedule:
            step = .commitments
        case .commitments:
            prefillProfileFromName()
            step = .profile
        case .profile:
            step = .health
        case .health:
            if selectedGender == .female && trackCycle {
                step = .cycle
            } else {
                step = .notifications
            }
        case .cycle:
            step = .notifications
        case .notifications:
            step = .ready
        default:
            break
        }
    }

    private func goBack() {
        guard let previous = StartStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: - Helpers

    private func prefillFromExisting() {
        if userName.isEmpty {
            userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        }
        if userName.isEmpty {
            userName = UserLifeProfileStore.load().preferredName
        }
        targetSleepHours = UserDefaults.standard.object(forKey: "targetSleepHours") as? Double ?? 8.0
        adhdFocusChallenge = UserDefaults.standard.string(forKey: "adhdFocusChallenge") ?? adhdFocusChallenge
        userKeyGoals = UserDefaults.standard.string(forKey: "userKeyGoals") ?? ""
        enableHealth = UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true

        let profile = UserLifeProfileStore.load()
        selectedGender = profile.gender
        structuredSections = LifeProfileComposer.parse(profile.profileText)
        fixedScheduleNotes = profile.fixedScheduleNotes
        focusPreference = profile.focusTimePreference

        let calendar = Calendar.current
        workStartTime = calendar.date(
            bySettingHour: profile.workStartHour,
            minute: profile.workStartMinute,
            second: 0,
            of: Date()
        ) ?? Self.defaultWorkStart
        workEndTime = calendar.date(
            bySettingHour: profile.workEndHour,
            minute: profile.workEndMinute,
            second: 0,
            of: Date()
        ) ?? Self.defaultWorkEnd
    }

    private func prefillProfileFromName() {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if structuredSections.adhdFocusPatterns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            structuredSections.adhdFocusPatterns = "I'm \(trimmed). Still learning my patterns — I'll teach the brain through day-end reflection."
        }
    }

    private func persistName() {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "userName")
        UserDefaults.standard.set(adhdFocusChallenge, forKey: "adhdFocusChallenge")
        UserDefaults.standard.set(userKeyGoals.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "userKeyGoals")
    }

    private func resolvedUserId() -> String {
        if !userId.isEmpty { return userId }
        return UserDefaults.standard.string(forKey: "saved_user_uid") ?? ""
    }

    private func organizeProfileWithAI() async {
        organizeError = nil
        isOrganizing = true
        defer { isOrganizing = false }

        let prompt = LifeProfileComposer.organizeStructuredPrompt(structuredSections)
        do {
            let polished = try await GLMService.shared.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.profileOrganizeSystem,
                tier: .economy
            )
            let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                structuredSections = LifeProfileComposer.organizeLocally(structuredSections)
                organizeError = "AI returned empty — formatted locally."
                return
            }
            structuredSections = LifeProfileComposer.parse(trimmed)
        } catch {
            structuredSections = LifeProfileComposer.organizeLocally(structuredSections)
            organizeError = "AI unavailable — formatted locally."
        }
    }

    private func saveAndFinish() {
        persistName()
        UserDefaults.standard.set(targetSleepHours, forKey: "targetSleepHours")
        UserDefaults.standard.set(enableHealth, forKey: "enableHealth")

        let calendar = Calendar.current
        var profile = UserLifeProfileStore.load()
        profile.hasCompletedOnboarding = true
        profile.profileText = lifeProfileMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? LifeProfileComposer.compile(structuredSections)
            : lifeProfileMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.fixedScheduleNotes = fixedScheduleNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.preferredName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.workStartHour = calendar.component(.hour, from: workStartTime)
        profile.workStartMinute = calendar.component(.minute, from: workStartTime)
        profile.workEndHour = calendar.component(.hour, from: workEndTime)
        profile.workEndMinute = calendar.component(.minute, from: workEndTime)

        if profile.workEndHour * 60 + profile.workEndMinute <= profile.workStartHour * 60 + profile.workStartMinute {
            profile.workEndHour = min(profile.workStartHour + 8, 23)
            profile.workEndMinute = profile.workStartMinute
        }

        profile.focusTimePreference = focusPreference
        profile.peakStartHour = profile.focusTimePreference.peakStartHour
        profile.peakEndHour = profile.focusTimePreference.peakEndHour
        profile.gender = selectedGender

        ProfileScheduleSync.enrichFixedScheduleNotes(profile: &profile, sections: structuredSections)
        UserLifeProfileStore.save(profile)

        if selectedGender == .female && trackCycle {
            let prefs = CycleTrackingPreferences(
                isEnabled: true,
                averageCycleLengthDays: cycleLengthDays,
                averagePeriodLengthDays: periodLengthDays,
                lastPeriodStart: Calendar.current.startOfDay(for: lastPeriodStart),
                usesHealthKit: enableHealth,
                commonSymptoms: Array(selectedCycleSymptoms).sorted()
            )
            CyclePreferencesStore.save(prefs)
        } else {
            CyclePreferencesStore.save(.default)
        }

        let markdown = profile.profileText.trimmingCharacters(in: .whitespacesAndNewlines)
        let uid = resolvedUserId()
        if !markdown.isEmpty {
            Task {
                _ = await shell.compileAndSaveLifeModel(markdown: markdown)
                if !uid.isEmpty {
                    await shell.assembleDayFromLifeModel(userId: uid)
                }
            }
        }

        onComplete(structuredSections)
    }

    private var workHoursLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return "\(f.string(from: workStartTime)) – \(f.string(from: workEndTime))"
    }

    private var healthSummaryLabel: String {
        if !enableHealth { return "Off" }
        if healthSync.syncPhase == .complete { return "Connected" }
        if healthSkipped { return "Skipped" }
        return "Enabled"
    }

    private func timePicker(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
                .foregroundColor(DesignSystem.textPrimary)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.vertical, 4)
    }

    private func checklistRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(DesignSystem.accentPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private static var defaultWorkStart: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static var defaultWorkEnd: Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Steps

private enum StartStep: Int, CaseIterable {
    case welcome = 0
    case name
    case gender
    case schedule
    case commitments
    case profile
    case health
    case cycle
    case notifications
    case ready

    static var questionCount: Int { allCases.count - 1 }

    var index: Int {
        max(rawValue, 1)
    }

    var progress: CGFloat {
        CGFloat(rawValue) / CGFloat(Self.allCases.count - 1)
    }

    var title: String {
        switch self {
        case .welcome: return "Welcome to \(UserFacingCopy.productName)"
        case .name: return "What should we call you?"
        case .gender: return "How do you identify?"
        case .schedule: return "Your typical work day"
        case .commitments: return "Fixed commitments"
        case .profile: return "Teach your brain your rhythms"
        case .health: return "Connect Apple Health"
        case .cycle: return "Your cycle"
        case .notifications: return "Stay on track"
        case .ready: return "You're all set"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "A quick setup so your planner knows you — nothing is guessed."
        case .name:
            return "We use your name in greetings and when the AI talks to you."
        case .gender:
            return "Personalizes features like cycle tracking. You can change this anytime."
        case .schedule:
            return "When you usually work, focus, and sleep — used for scheduling."
        case .commitments:
            return "Meetings and routines that must stay at the same time every day."
        case .profile:
            return "Personality, ADHD patterns, and how you want the AI to plan."
        case .health:
            return "Optional but recommended — sleep and recovery shape your daily capacity."
        case .cycle:
            return "Optional — helps \(UserFacingCopy.productName) learn your rhythm and give phase-aware coaching."
        case .notifications:
            return "Optional — up to 2 calm reminders per day for meds, meetings, and tasks. No spam."
        case .ready:
            return "Review below, then we'll build your first day."
        }
    }
}

#Preview {
    OnboardingView(
        userId: "preview",
        healthSync: HealthSyncService.shared,
        onComplete: { _ in }
    )
    .environmentObject(AppShellState())
}
