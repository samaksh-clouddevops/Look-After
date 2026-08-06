import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

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

    @State private var orbState: LABrainVoiceOrbState = .ready
    @State private var statusLine: String?
    @State private var responseSubtitle: String?

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: DesignSystem.spacingLG) {
                headerSection
                statusRow
                Spacer(minLength: DesignSystem.spacingMD)

                LABrainVoiceOrb(state: orbState, onTap: handleOrbTap)
                    .featureTourAnchor(.brainVoiceOrb, cornerRadius: 110)
                    .id(AppFeatureTourAnchorID.brainVoiceOrb.rawValue)

                contextCopy

                if let responseSubtitle {
                    Text(responseSubtitle)
                        .textStyleBody(color: DesignSystem.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, DesignSystem.spacingMD)
                        .transition(.opacity)
                }

                Spacer(minLength: DesignSystem.spacingMD)

                decideForMeChip
                askBrainGhostButton
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
            .padding(.top, DesignSystem.spacingSM)
            .padding(.bottom, DesignSystem.spacingXXL)
        }
        .accessibilityIdentifier("screen-brain-dashboard")
        .task {
            await brainVM.refresh(userId: userId)
            await onRefresh()
        }
        .onChange(of: speechSynthesizer.isSpeaking) { _, speaking in
            if !speaking, orbState == .speaking {
                orbState = .ready
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
                .textStyleCaption(color: DesignSystem.textMuted)
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
            .textStyleBody(color: DesignSystem.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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

    private func handleOrbTap() {
        switch orbState {
        case .ready:
            Task { await startListening() }
        case .listening:
            finishListeningAndSend()
        case .thinking:
            break
        case .speaking:
            speechSynthesizer.stop()
            orbState = .ready
            statusLine = nil
        }
    }

    private func startListening() async {
        orbState = .listening
        statusLine = "Listening…"
        responseSubtitle = nil
        await speechManager.startListening()
    }

    private func finishListeningAndSend() {
        speechManager.stopListening()
        let message = speechManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            orbState = .ready
            statusLine = nil
            return
        }

        orbState = .thinking
        statusLine = "Thinking…"

        Task {
            // Let the mic session fully release before playback TTS starts.
            try? await Task.sleep(nanoseconds: 200_000_000)

            let response = await brain.chat(message: message)
            await MainActor.run {
                let rawReply = response.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawReply.isEmpty else {
                    orbState = .ready
                    statusLine = "I didn't catch that — try again."
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
                    }
                } else {
                    orbState = .ready
                }
            }
        }
    }
}
