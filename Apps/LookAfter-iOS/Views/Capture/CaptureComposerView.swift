import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Single-screen capture composer — field-first Notes-style compose.
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
        NavigationStack {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                header

                TextField("What's on your mind?", text: $text, axis: .vertical)
                    .lineLimit(3...10)
                    .focused($isFocused)
                    .textStyleBody()
                    .padding(DesignSystem.spacingMD)
                    .frame(minHeight: 120, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                            .fill(DesignSystem.contentSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                                    .stroke(DesignSystem.border, lineWidth: 1)
                            )
                    )
                    .accessibilityIdentifier("capture-text-field")
                    .padding(.horizontal, DesignSystem.screenHorizontal)

                // Field accessories: Speak + type menu (chips no longer ahead of content).
                HStack(spacing: DesignSystem.spacingSM) {
                    Button(action: toggleVoice) {
                        Label(
                            speechManager.isListening ? "Stop" : "Speak",
                            systemImage: speechManager.isListening ? "waveform.circle.fill" : "mic.fill"
                        )
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(speechManager.isListening ? DesignSystem.focus : DesignSystem.accentPrimary)
                        .frame(minHeight: DesignSystem.minTouchTarget)
                        .padding(.horizontal, DesignSystem.spacingSM)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("capture-mic")

                    if speechManager.isListening {
                        AudioWaveformView(levels: speechManager.audioLevels)
                            .frame(maxWidth: 120)
                    }

                    Menu {
                        Button("Auto") { selectedChip = nil }
                        ForEach(chips, id: \.self) { intent in
                            Button(chipLabel(intent)) { selectedChip = intent }
                        }
                    } label: {
                        Label(selectedChipLabel, systemImage: "tag")
                            .font(.dsCaption(weight: .semibold))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .frame(minHeight: DesignSystem.minTouchTarget)
                            .padding(.horizontal, DesignSystem.spacingSM)
                    }
                    .accessibilityIdentifier("capture-type-menu")
                    .accessibilityLabel("Capture type, \(selectedChipLabel)")

                    Spacer(minLength: 0)

                    if let error = speechManager.errorMessage {
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.accentPrimary)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Settings for microphone access")
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.warning)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, DesignSystem.screenHorizontal)

                if selectedChip == .mood {
                    moodSlider
                }
                if selectedChip == .event {
                    DatePicker("When", selection: $eventDate)
                        .datePickerStyle(.compact)
                        .padding(.horizontal, DesignSystem.screenHorizontal)
                }

                if !canSave {
                    Text("Type or speak to enable Save")
                        .font(.dsCaption())
                        .foregroundStyle(DesignSystem.textSecondary)
                        .padding(.horizontal, DesignSystem.screenHorizontal)
                        .accessibilityIdentifier("capture-save-helper")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: DesignSystem.spacingSM) {
                    saveArea
                    if canSave {
                        inboxFooterLink
                    }
                }
                .padding(.top, DesignSystem.spacingSM)
                .padding(.bottom, DesignSystem.spacingSM)
                .frame(maxWidth: .infinity)
                .background(DesignSystem.backgroundPrimary.opacity(0.96))
            }
            .background(DesignSystem.backgroundPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: DesignSystem.spacingSM) {
                        Menu {
                            Button("View inbox", systemImage: "tray.full", action: onOpenInbox)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DesignSystem.textSecondary)
                                .frame(width: DesignSystem.minTouchTarget, height: DesignSystem.minTouchTarget)
                        }
                        .accessibilityIdentifier("capture-overflow")
                        .accessibilityLabel("More")

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.textSecondary)
                                .frame(width: DesignSystem.minTouchTarget, height: DesignSystem.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("capture-dismiss-fab")
                        .accessibilityLabel("Close")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
        .padding(.top, DesignSystem.spacingMD)
        .padding(.horizontal, DesignSystem.screenHorizontal)
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

    private var selectedChipLabel: String {
        guard let selectedChip else { return "Auto" }
        return chipLabel(selectedChip)
    }

    @ViewBuilder
    private var saveArea: some View {
        Button(action: save) {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(canSave ? DesignSystem.accentOnPrimary : DesignSystem.textSecondary)
                }
                Text(isSaving ? "Saving…" : "Save")
                    .font(.dsBody(weight: .semibold))
                    .foregroundStyle(canSave ? DesignSystem.accentOnPrimary : DesignSystem.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: DesignSystem.minTouchTarget)
        }
        .modifier(CaptureSaveChrome(isEnabled: canSave && !isSaving))
        .disabled(!canSave || isSaving)
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .accessibilityIdentifier(canSave ? "capture-save" : "capture-save-disabled")
        .accessibilityLabel(canSave ? "Save" : "Save unavailable")
        .accessibilityHint(canSave ? "Saves your capture" : "Type or speak something first")
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

private struct CaptureSaveChrome: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .buttonStyle(.glassProminent)
                .tint(LookAfterChrome.accentTint)
        } else {
            content
                .buttonStyle(.plain)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignSystem.contentSurface)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(DesignSystem.border, lineWidth: 1)
                        )
                )
        }
    }
}
