import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures
#if os(iOS)
import AudioToolbox
#endif

/// Brain tab — voice-first psychologist companion with optional text chat.
struct BrainDashboardView: View {

    @ObservedObject var brainVM: BrainViewModel
    @ObservedObject var adhdVM: ADHDViewModel
    @ObservedObject var brain: ExecutiveBrain
    @ObservedObject var speechManager: SpeechRecognitionManager
    @ObservedObject var speechSynthesizer: PlanningSpeechSynthesizer
    let userId: String
    let onStartHero: (LifeTask?) -> Void
    let onRescheduleHero: (LifeTask) -> Void
    let onDecideForMe: () -> Void
    let onCapture: () -> Void
    let onResume: (String?) -> Void
    let onMarkMedicationTaken: (String) -> Void
    let onNavigateToTasks: () -> Void
    let onNavigateToCoach: () -> Void
    let onReset: () -> Void
    let onRefresh: () async -> Void
    /// Routes scheduling / task-creation voice requests through Executive Planning (creates tasks on the timeline).
    var onExecutivePlan: ((String) async -> String)? = nil
    /// Whether the planning conversation already has turns from this session.
    var hasPriorVoiceConversation: Bool = false

    @State private var orbState: LABrainVoiceOrbState = .ready
    @State private var statusLine: String?
    @State private var responseSubtitle: String?
    @State private var isConversationActive = false
    @State private var proactiveWelcomeTask: Task<Void, Never>?
    @State private var didDeliverProactiveWelcome = false

    private let proactiveWelcomeDelayNs: UInt64 = 3_500_000_000

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: DesignSystem.spacingMD) {
                headerSection
                statusRow

                LABrainVoiceOrb(state: orbState, onTap: handleOrbTap)
                    #if os(iOS)
                    .featureTourAnchor(.brainVoiceOrb, cornerRadius: 110)
                    .id(AppFeatureTourAnchorID.brainVoiceOrb.rawValue)
                    #endif
                    .padding(.vertical, DesignSystem.spacingXS)

                Text(orbHint)
                    .textStyleCaption(color: DesignSystem.textSecondary)
                    .multilineTextAlignment(.center)

                if let responseSubtitle {
                    Text(responseSubtitle)
                        .textStyleBody(color: DesignSystem.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .minimumScaleFactor(0.92)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DesignSystem.spacingMD)
                        .transition(.opacity)
                }

                Spacer(minLength: DesignSystem.spacingSM)

                decideForMeChip
                    .frame(maxWidth: .infinity)
                askBrainTextButton
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
            .padding(.top, DesignSystem.spacingSM)
            .padding(.bottom, DesignSystem.spacingXL)
        }
        .accessibilityIdentifier("screen-brain-dashboard")
        .task {
            await brainVM.refresh(userId: userId)
        }
        .onAppear {
            scheduleProactiveWelcome()
        }
        .onDisappear {
            proactiveWelcomeTask?.cancel()
            proactiveWelcomeTask = nil
        }
        .onChange(of: speechSynthesizer.isSpeaking) { _, speaking in
            if !speaking, orbState == .speaking {
                orbState = .ready
                resumeListeningIfNeeded()
            }
        }
        .onChange(of: brain.isThinking) { _, thinking in
            // Only mirror Brain thinking during an active voice turn — never lock the orb
            // because Briefing / Day Audit / other screens kicked off a chat.
            guard isConversationActive else { return }
            if thinking {
                if orbState != .speaking {
                    orbState = .thinking
                    statusLine = "Thinking…"
                }
            } else if orbState == .thinking {
                orbState = .ready
                statusLine = nil
                resumeListeningIfNeeded()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("Executive Brain")
                .textStyleScreenTitle()

            Spacer()

            Menu(content: {
                Button(action: onNavigateToTasks) {
                    Label("All tasks", systemImage: "checklist")
                }
                Button(action: onCapture) {
                    Label("Capture", systemImage: "plus.circle")
                }
                Button(action: onDecideForMe) {
                    Label("Decide for me", systemImage: "sparkles")
                }
                Button(action: {
                    adhdVM.startBodyDoubling()
                }, label: {
                    Label("Body doubling", systemImage: "person.2.fill")
                })
                if adhdVM.lastInterruptedTask != nil {
                    Button(action: {
                        onResume(adhdVM.lastInterruptedTask?.id)
                    }, label: {
                        Label("Resume last session", systemImage: "play.circle")
                    })
                }
                Button(action: onReset) {
                    Label("Reset", systemImage: "heart.flow.fill")
                }
            }, label: {
                Image(systemName: "ellipsis.circle")
                    .font(.dsIcon())
                    .foregroundColor(DesignSystem.textSecondary)
                    .frame(width: 44, height: 44)
            })
            .accessibilityLabel("More")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if let statusLine {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                Text(statusLine)
                    .textStyleCaption(color: DesignSystem.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if orbState == .ready {
            Text("I'm here when you're ready.")
                .textStyleCaption(color: DesignSystem.textPrimary.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusDotColor: Color {
        switch orbState {
        case .listening: return DesignSystem.accentPrimary
        case .thinking: return DesignSystem.textSecondary
        default: return DesignSystem.textMuted
        }
    }

    private var orbHint: String {
        switch orbState {
        case .ready: return "Tap the orb to speak"
        case .listening: return "Listening — tap to end"
        case .thinking: return "Thinking — tap to cancel"
        case .speaking: return "Speaking — tap to skip"
        }
    }

    private var decideForMeChip: some View {
        Button(action: onDecideForMe) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: "sparkles")
                    .font(.dsIcon())
                Text("Decide for me")
                    .font(.dsBody(weight: .semibold))
            }
            .foregroundStyle(DesignSystem.accentOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DesignSystem.minTouchTarget)
        }
        .buttonStyle(.glassProminent)
        .tint(LookAfterChrome.accentTint)
        .accessibilityIdentifier("brain-decide-entry")
        .accessibilityLabel("Decide for me")
    }

    private var askBrainTextButton: some View {
        Button(action: onNavigateToCoach) {
            Text("Ask Brain")
                .font(.dsCaption(weight: .semibold))
                .foregroundStyle(DesignSystem.accentPrimary)
                .frame(minHeight: DesignSystem.minTouchTarget)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brain-ask-entry")
        .accessibilityLabel("Ask Brain")
    }

    // MARK: - Voice flow

    private func scheduleProactiveWelcome() {
        proactiveWelcomeTask?.cancel()
        didDeliverProactiveWelcome = false

        proactiveWelcomeTask = Task {
            try? await Task.sleep(nanoseconds: proactiveWelcomeDelayNs)
            guard !Task.isCancelled else { return }
            await deliverProactiveWelcomeIfNeeded()
        }
    }

    private func deliverProactiveWelcomeIfNeeded() async {
        guard !didDeliverProactiveWelcome else { return }
        guard !UITestLaunchConfiguration.isEnabled else {
            didDeliverProactiveWelcome = true
            return
        }
        guard !isConversationActive else { return }
        guard orbState == .ready else { return }
        guard !speechSynthesizer.isSpeaking, !brain.isThinking else { return }

        didDeliverProactiveWelcome = true
        isConversationActive = true

        let welcome = BrainVoiceWelcomeBuilder.message(
            presentation: brainVM.presentation,
            userName: UserLifeProfileStore.resolvedDisplayName(),
            hasPriorConversation: hasPriorVoiceConversation
        )

        playWelcomeCue()

        let spoken = SpeechTextPreprocessor.prepareForSpeech(welcome)
        responseSubtitle = spoken.isEmpty ? welcome : spoken
        statusLine = nil

        if SpeechVoiceSettings.autoSpeakReplies {
            orbState = .speaking
            speechSynthesizer.speak(spoken.isEmpty ? welcome : spoken)
            if !speechSynthesizer.isSpeaking {
                orbState = .ready
                await startListening()
            }
        } else {
            orbState = .ready
            await startListening()
        }
    }

    private func playWelcomeCue() {
        HapticManager.notification(.success)
        #if os(iOS)
        AudioServicesPlaySystemSound(1104)
        #endif
    }

    private func cancelProactiveWelcome() {
        proactiveWelcomeTask?.cancel()
        proactiveWelcomeTask = nil
        didDeliverProactiveWelcome = true
    }

    private func handleOrbTap() {
        // B5 / S19: one start path. Orb tap is the *voice* entry for the same job as
        // "Decide for me" (help me decide) — not a third unrelated product path.
        // Ready → start listening; listening → end; speaking → stop TTS;
        // thinking → cancel so the UI never feels frozen.
        switch orbState {
        case .ready:
            cancelProactiveWelcome()
            isConversationActive = true
            Task { await startListening() }
        case .listening:
            endConversation()
        case .thinking:
            cancelInFlightVoiceTurn()
        case .speaking:
            speechSynthesizer.stop()
            orbState = .ready
            statusLine = nil
            resumeListeningIfNeeded()
        }
    }

    private func cancelInFlightVoiceTurn() {
        speechSynthesizer.stop()
        speechManager.onUtteranceComplete = nil
        speechManager.autoCommitEnabled = false
        speechManager.stopListening()
        orbState = .ready
        statusLine = "Cancelled — tap to speak again."
        // Keep conversation active so a follow-up tap can listen immediately.
        isConversationActive = true
    }

    private func endConversation() {
        cancelProactiveWelcome()
        isConversationActive = false
        speechManager.onUtteranceComplete = nil
        speechManager.autoCommitEnabled = false
        speechManager.stopListening()
        speechSynthesizer.stop()
        orbState = .ready
        statusLine = nil
    }

    private func resumeListeningIfNeeded() {
        guard isConversationActive, orbState == .ready else { return }
        Task { await startListening() }
    }

    private func startListening() async {
        guard orbState != .thinking else { return }
        // UITests must not trip Speech permission alerts mid-navigation.
        if UITestLaunchConfiguration.isEnabled {
            orbState = .ready
            statusLine = nil
            return
        }
        orbState = .listening
        statusLine = "Listening…"
        responseSubtitle = nil

        speechManager.autoCommitEnabled = true
        speechManager.autoCommitSilenceDuration = 1.2
        speechManager.onUtteranceComplete = { message in
            Task { await sendVoiceMessage(message) }
        }
        await speechManager.startListening()

        // Permission / mic failure leaves isListening false — don't trap the orb.
        if !speechManager.isListening {
            orbState = .ready
            statusLine = speechManager.errorMessage
                ?? (speechManager.permissionDenied
                    ? "Microphone or speech permission needed."
                    : "Couldn't start listening — tap to retry.")
        }
    }

    private func sendVoiceMessage(_ message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resumeListeningIfNeeded()
            return
        }
        guard orbState != .thinking else { return }

        orbState = .thinking
        statusLine = "Thinking…"
        VoiceSessionKeepAlive.begin("brain-voice-thinking")
        defer { VoiceSessionKeepAlive.end("brain-voice-thinking") }

        // Let the mic session fully release before playback TTS starts.
        try? await Task.sleep(nanoseconds: 80_000_000)

        // Always route through Executive Planning so voice turns share one conversation history.
        let response: String
        if let onExecutivePlan {
            response = await onExecutivePlan(trimmed)
        } else {
            response = await brain.chat(message: trimmed)
        }

        // User may have cancelled mid-flight.
        guard isConversationActive, orbState == .thinking else { return }

        let rawReply = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawReply.isEmpty else {
            orbState = .ready
            statusLine = "I didn't catch that — try again."
            resumeListeningIfNeeded()
            return
        }

        let reply = SpeechTextPreprocessor.prepareForSpeech(rawReply)
        responseSubtitle = reply.isEmpty ? rawReply : reply
        statusLine = nil

        if SpeechVoiceSettings.autoSpeakReplies {
            orbState = .speaking
            speechSynthesizer.speak(reply.isEmpty ? rawReply : reply)
            // Cloud TTS sets isSpeaking immediately; Apple path does too.
            // If both fail synchronously, recover.
            if !speechSynthesizer.isSpeaking {
                orbState = .ready
                statusLine = speechSynthesizer.lastError ?? "Couldn't play voice reply."
                resumeListeningIfNeeded()
            }
        } else {
            orbState = .ready
            resumeListeningIfNeeded()
        }
    }
}
