import SwiftUI
import LookAfterCore
import LookAfterFeatures

struct ExecutiveCaptureSheet: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var text = ""
    @State private var confirmation: String?
    @FocusState private var isFocused: Bool

    let userId: String

    var body: some View {
        ZStack {
            CinematicBackground(accentIntensity: 0.15)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(DesignSystem.textMuted)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                if let confirmation {
                    Text(confirmation)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismiss() }
                        }
                } else {
                    captureField
                }

                Spacer()

                if confirmation == nil {
                    captureActions
                        .padding(.bottom, 48)
                }
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: speechManager.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            text = transcript
        }
        .keyboardDismissToolbar(label: "Done")
    }

    private var captureField: some View {
        TextField("", text: $text, prompt: capturePrompt, axis: .vertical)
            .lineLimit(1...8)
            .focused($isFocused)
            .font(.system(size: 32, weight: .regular))
            .foregroundColor(DesignSystem.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
    }

    private var capturePrompt: Text {
        Text("Don't let me forget…")
            .font(.system(size: 32, weight: .regular))
            .foregroundColor(DesignSystem.textMuted.opacity(0.35))
    }

    private var captureActions: some View {
        HStack(spacing: 56) {
            Button(action: toggleVoice) {
                Image(systemName: speechManager.isListening ? "waveform" : "mic")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(speechManager.isListening ? DesignSystem.accentPrimary : DesignSystem.textMuted.opacity(0.6))
            }
            .accessibilityLabel("Speak")

            Button(action: submit) {
                Text("Remember this")
                    .font(.dsHeadline())
                    .foregroundColor(text.isEmpty ? DesignSystem.textMuted.opacity(0.25) : DesignSystem.accentPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(text.isEmpty ? 0.04 : 0.08))
                    )
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isFocused = false
        KeyboardDismiss.dismiss()
        HapticManager.notification(.success)
        shell.contextOrchestrator.captureNote(trimmed, userId: userId)
        Task {
            await shell.inboxVM.captureAndProcess(text: trimmed)
            withAnimation {
                confirmation = "Got it"
            }
        }
    }

    private func toggleVoice() {
        if speechManager.isListening {
            speechManager.stopListening()
        } else {
            Task { await speechManager.startListening() }
        }
    }
}
