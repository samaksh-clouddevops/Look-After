import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Single-screen capture composer — voice/text first, optional type chips.
struct CaptureComposerView: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechManager = SpeechRecognitionManager()

    let userId: String
    var source: CaptureSource = .bottomNav
    var contextHints: CaptureContextHints = CaptureContextHints()
    var onOpenInbox: () -> Void = {}
    var onRouted: (CaptureRouteResult) -> Void = { _ in }

    @State private var text = ""
    @State private var selectedChip: CaptureIntent?
    @State private var moodLevel: Double = 0.5
    @State private var eventDate = Date()
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    private let chips: [CaptureIntent] = [.task, .note, .event, .mood, .insight]

    var body: some View {
        ZStack(alignment: .bottom) {
            DesignSystem.backgroundPrimary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                header
                composerField
                if selectedChip == .mood {
                    moodSlider
                }
                if selectedChip == .event {
                    DatePicker("When", selection: $eventDate)
                        .datePickerStyle(.compact)
                        .padding(.horizontal, DesignSystem.screenHorizontal)
                }
                chipRow
                saveButton
                inboxFooterLink
                Spacer(minLength: 0)
            }

            LADismissFAB { dismiss() }
                .padding(.bottom, DesignSystem.spacingXXXL)
        }
        .accessibilityIdentifier("capture-composer")
        .onAppear {
            isFocused = true
            if selectedChip == nil, let preset = contextHints.preselectedIntent {
                selectedChip = preset
            }
        }
        .onChange(of: speechManager.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            text = transcript
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
            Text("Capture")
                .textStyleScreenTitle()
            Text("Say or type anything — we'll put it in the right place.")
                .textStyleBody(color: DesignSystem.textSecondary)
        }
        .padding(.top, DesignSystem.spacingXL)
        .padding(.horizontal, DesignSystem.screenHorizontal)
    }

    private var composerField: some View {
        VStack(spacing: DesignSystem.spacingSM) {
            TextField("What's on your mind?", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .focused($isFocused)
                .textStyleBody()
                .padding(DesignSystem.spacingMD)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .fill(DesignSystem.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                .stroke(DesignSystem.border, lineWidth: 1)
                        )
                )
                .accessibilityIdentifier("capture-text-field")
                .padding(.horizontal, DesignSystem.screenHorizontal)

            HStack(spacing: DesignSystem.spacingMD) {
                Button(action: toggleVoice) {
                    Label(
                        speechManager.isListening ? "Stop" : "Speak",
                        systemImage: speechManager.isListening ? "waveform.circle.fill" : "mic.circle.fill"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(speechManager.isListening ? DesignSystem.focus : DesignSystem.textSecondary)
                }
                .accessibilityIdentifier("capture-mic")

                if speechManager.isListening {
                    AudioWaveformView(levels: speechManager.audioLevels)
                        .padding(.horizontal, DesignSystem.screenHorizontal)
                }

                Spacer()

                if let error = speechManager.errorMessage {
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                    .accessibilityLabel("Open Settings for microphone access")
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.warning)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
        }
    }

    private var moodSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How are you feeling?")
                .textStyleSectionLabel()
            Slider(value: $moodLevel, in: 0...1)
            Text(moodLabel)
                .textStyleCaption()
        }
        .padding(.horizontal, DesignSystem.screenHorizontal)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "Auto", intent: nil)
                ForEach(chips, id: \.self) { intent in
                    chipButton(label: chipLabel(intent), intent: intent)
                }
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
        }
    }

    private func chipButton(label: String, intent: CaptureIntent?) -> some View {
        let isSelected = selectedChip == intent
        return Button {
            HapticManager.impact(.light)
            selectedChip = isSelected ? nil : intent
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? DesignSystem.accentOnPrimary : DesignSystem.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? DesignSystem.accentPrimary : DesignSystem.backgroundElevated)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(intent.map { "capture-chip-\($0.rawValue)" } ?? "capture-chip-auto")
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack {
                if isSaving {
                    ProgressView().tint(DesignSystem.accentOnPrimary)
                }
                Text(isSaving ? "Saving…" : "Save")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundColor(DesignSystem.accentOnPrimary)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .fill(canSave ? DesignSystem.accentPrimary : DesignSystem.textMuted.opacity(0.4))
            )
        }
        .disabled(!canSave || isSaving)
        .buttonStyle(.plain)
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .accessibilityIdentifier("capture-save")
    }

    private var inboxFooterLink: some View {
        Button(action: onOpenInbox) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: "tray.full")
                Text("View inbox")
                if shell.inboxVM.unprocessedCount > 0 {
                    Text("\(shell.inboxVM.unprocessedCount)")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.accentOnPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignSystem.accentPrimary.opacity(0.15)))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(DesignSystem.textMuted)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(DesignSystem.textPrimary)
            .padding(.horizontal, DesignSystem.screenHorizontal)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-view-inbox")
    }

    private var canSave: Bool {
        if selectedChip == .mood { return true }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var moodLabel: String {
        switch moodLevel {
        case ..<0.33: return "Low"
        case ..<0.66: return "Okay"
        default: return "Good"
        }
    }

    private func chipLabel(_ intent: CaptureIntent) -> String {
        switch intent {
        case .task: return "Task"
        case .note: return "Note"
        case .event: return "Event"
        case .mood: return "Mood"
        case .insight: return "Insight"
        case .auto: return "Auto"
        }
    }

    private func toggleVoice() {
        HapticManager.impact(.medium)
        if speechManager.isListening {
            speechManager.stopListening()
        } else {
            Task { await speechManager.startListening() }
        }
    }

    private func save() {
        guard canSave else { return }
        isFocused = false
        KeyboardDismiss.dismiss()
        HapticManager.notification(.success)
        isSaving = true

        var payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedChip == .mood && payload.isEmpty {
            payload = "Feeling \(moodLabel.lowercased())"
        }

        var hints = contextHints
        hints.moodLevel = selectedChip == .mood ? moodLevel : contextHints.moodLevel
        hints.preselectedDate = selectedChip == .event ? eventDate : contextHints.preselectedDate

        let request = CaptureRequest(
            text: payload,
            voiceTranscript: speechManager.isListening || !speechManager.transcript.isEmpty,
            hintedIntent: selectedChip,
            source: source,
            contextHints: hints
        )

        Task {
            let result = await shell.inboxVM.routeCapture(request, userId: userId)
            shell.contextOrchestrator.captureNote(payload, userId: userId)
            isSaving = false
            onRouted(result)
            dismiss()
        }
    }
}

/// Backward-compatible wrapper — presents CaptureComposerView.
struct ExecutiveCaptureSheet: View {
    let userId: String
    var source: CaptureSource = .bottomNav
    var contextHints: CaptureContextHints = CaptureContextHints()
    var onOpenInbox: () -> Void = {}
    var onRouted: (CaptureRouteResult) -> Void = { _ in }

    var body: some View {
        CaptureComposerView(
            userId: userId,
            source: source,
            contextHints: contextHints,
            onOpenInbox: onOpenInbox,
            onRouted: onRouted
        )
        .accessibilityIdentifier("screen-capture")
    }
}
