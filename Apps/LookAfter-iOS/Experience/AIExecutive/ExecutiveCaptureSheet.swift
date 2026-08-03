import SwiftUI
import LookAfterCore
import LookAfterFeatures

private enum CaptureQuickType: String, CaseIterable, Identifiable {
    case task = "Task"
    case idea = "Idea"
    case journal = "Journal"
    case reminder = "Reminder"
    case health = "Health"
    case expense = "Expense"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .task: return "checkmark.circle"
        case .idea: return "lightbulb"
        case .journal: return "book"
        case .reminder: return "bell"
        case .health: return "heart"
        case .expense: return "indianrupeesign.circle"
        }
    }
}

struct ExecutiveCaptureSheet: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var text = ""
    @State private var selectedType: CaptureQuickType = .task
    @State private var confirmation: String?
    @FocusState private var isFocused: Bool

    let userId: String

    var body: some View {
        ZStack {
            DesignSystem.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(DesignSystem.textMuted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close capture")
                }
                .padding(.horizontal, DesignSystem.screenHorizontal)

                Spacer()

                if let confirmation {
                    Text(confirmation)
                        .font(.dsLargeTitle())
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
                    quickTypeChips
                        .padding(.bottom, DesignSystem.spacingLG)
                    captureActions
                        .padding(.bottom, DesignSystem.spacingXXXL)
                }
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: speechManager.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            text = transcript
        }
        .keyboardDismissToolbar(label: "Done")
        .accessibilityIdentifier("screen-voice-capture")
    }

    private var captureField: some View {
        TextField("", text: $text, prompt: capturePrompt, axis: .vertical)
            .lineLimit(1...8)
            .focused($isFocused)
            .font(.dsLargeTitle())
            .foregroundColor(DesignSystem.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignSystem.screenHorizontal)
    }

    private var capturePrompt: Text {
        Text("What's on your mind?")
            .font(.dsLargeTitle())
            .foregroundColor(DesignSystem.textMuted.opacity(0.45))
    }

    private var quickTypeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.spacingSM) {
                ForEach(CaptureQuickType.allCases) { type in
                    Button {
                        selectedType = type
                        HapticManager.impact(.light)
                    } label: {
                        Label(type.rawValue, systemImage: type.icon)
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(selectedType == type ? DesignSystem.accentOnPrimary : DesignSystem.textPrimary)
                            .padding(.horizontal, DesignSystem.spacingMD)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(selectedType == type ? DesignSystem.accentPrimary : DesignSystem.backgroundSecondary)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(DesignSystem.border, lineWidth: selectedType == type ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(type.rawValue) capture type")
                    .accessibilityAddTraits(selectedType == type ? .isSelected : [])
                }
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
        }
    }

    private var captureActions: some View {
        HStack(spacing: DesignSystem.spacingHero) {
            Button(action: toggleVoice) {
                Image(systemName: speechManager.isListening ? "waveform.circle.fill" : "mic.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(speechManager.isListening ? DesignSystem.accentPrimary : DesignSystem.textMuted)
            }
            .accessibilityLabel("Speak")

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(text.isEmpty ? DesignSystem.textMuted : DesignSystem.accentOnPrimary)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(text.isEmpty ? DesignSystem.backgroundElevated : DesignSystem.accentPrimary)
                    )
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Save capture")
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isFocused = false
        KeyboardDismiss.dismiss()
        HapticManager.notification(.success)
        let prefixed = "[\(selectedType.rawValue)] \(trimmed)"
        shell.contextOrchestrator.captureNote(prefixed, userId: userId)
        Task {
            await shell.inboxVM.captureAndProcess(text: prefixed)
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
