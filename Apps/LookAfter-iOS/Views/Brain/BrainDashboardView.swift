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
                    .featureTourAnchor(.brainVoiceOrb, cornerRadius: 110)
                    .id(AppFeatureTourAnchorID.brainVoiceOrb.rawValue)
                    .padding(.vertical, DesignSystem.spacingSM)

                contextCopy

                if let responseSubtitle {
                    Text(responseSubtitle)
                        .textStyleBody(color: DesignSystem.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, DesignSystem.spacingMD)
                        .transition(.opacity)
                }

                Spacer(minLength: DesignSystem.spacingLG)

                decideForMeChip
                askBrainGhostButton
                siriHint
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
        .onChange(of: orbState) { _, state in
            if state == .thinking {
                VoiceSessionKeepAlive.begin("brain-voice-thinking")
            } else {
                VoiceSessionKeepAlive.end("brain-voice-thinking")
            }
        }
        .onChange(of: brain.isThinking) { _, thinking in
            if thinking {
                orbState = .thinking
                statusLine = "Thinking…"
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
            .accessibilityLabel("Brain actions")
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
                .textStyleCaption(color: DesignSystem.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusDotColor: Color {
        switch orbState {
        case .listening: return DesignSystem.health
        case .thinking: return DesignSystem.focus
        default: return DesignSystem.textMuted
        }
    }

    private var contextCopy: some View {
        Text("Analyzing your context, commitments, energy, and goals to help you decide.")
            .textStyleBody(color: DesignSystem.textPrimary.opacity(0.72))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var siriHint: some View {
        Text(isConversationActive
             ? "Speak naturally — I'll listen and reply. Tap the orb to end."
             : "I'll check in shortly — or tap the orb to start now.")
            .textStyleCaption(color: DesignSystem.textMuted)
            .multilineTextAlignment(.center)
            .padding(.top, DesignSystem.spacingXS)
            .accessibilityHint("Voice input via the orb or Siri shortcut")
    }

    private var decideForMeChip: some View {
        Button(action: onDecideForMe) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: "sparkles")
                    .font(.dsIcon())
                Text("Decide for me")
                    .textStyleCardTitle()
            }
            .foregroundColor(DesignSystem.accentPrimary)
            .padding(.horizontal, DesignSystem.spacingLG)
            .padding(.vertical, DesignSystem.spacingMD)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignSystem.accentPrimary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brain-decide-entry")
        .accessibilityLabel("Decide for me")
    }

    private var askBrainGhostButton: some View {
        Button(action: onNavigateToCoach) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: "bubble.left")
                    .font(.dsIcon())
                Text("Ask Brain")
                    .textStyleCardTitle()
            }
            .foregroundColor(DesignSystem.textPrimary)
            .padding(.horizontal, DesignSystem.spacingLG)
            .padding(.vertical, DesignSystem.spacingMD)
            .background(
                Capsule(style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
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
        switch orbState {
        case .ready:
            cancelProactiveWelcome()
            isConversationActive = true
            Task { await startListening() }
        case .listening:
            endConversation()
        case .thinking:
            break
        case .speaking:
            speechSynthesizer.stop()
            orbState = .ready
            statusLine = nil
            resumeListeningIfNeeded()
        }
    }

    private func endConversation() {
        cancelProactiveWelcome()
        isConversationActive = false
        speechManager.onUtteranceComplete = nil
        speechManager.autoCommitEnabled = false
        speechManager.stopListening()
        orbState = .ready
        statusLine = nil
    }

    private func resumeListeningIfNeeded() {
        guard isConversationActive, orbState == .ready else { return }
        Task { await startListening() }
    }

    private func startListening() async {
        guard orbState != .thinking else { return }
        orbState = .listening
        statusLine = "Listening…"
        responseSubtitle = nil

        speechManager.autoCommitEnabled = true
        speechManager.autoCommitSilenceDuration = 1.2
        speechManager.onUtteranceComplete = { message in
            Task { await sendVoiceMessage(message) }
        }
        await speechManager.startListening()
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

        // Let the mic session fully release before playback TTS starts.
        try? await Task.sleep(nanoseconds: 80_000_000)

        // Always route through Executive Planning so voice turns share one conversation history.
        let response: String
        if let onExecutivePlan {
            response = await onExecutivePlan(trimmed)
        } else {
            response = await brain.chat(message: trimmed)
        }

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
            if !speechSynthesizer.isSpeaking {
                orbState = .ready
                statusLine = "Couldn't play voice reply."
                resumeListeningIfNeeded()
            }
        } else {
            orbState = .ready
            resumeListeningIfNeeded()
        }
    }
}
