import SwiftUI
import LookAfterCore
import LookAfterFeatures

private enum CaptureMenuType: String, CaseIterable, Identifiable {
    case task = "Task"
    case note = "Note"
    case event = "Event"
    case health = "Health"
    case insight = "Insight"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .task: return "To do or follow up"
        case .note: return "Thoughts or ideas"
        case .event: return "Add to calendar"
        case .health: return "Log health or mood"
        case .insight: return "Something to remember"
        }
    }

    var icon: String {
        switch self {
        case .task: return "checkmark.circle"
        case .note: return "note.text"
        case .event: return "calendar"
        case .health: return "heart"
        case .insight: return "sparkles"
        }
    }

    var iconColor: Color {
        switch self {
        case .task: return DesignSystem.health
        case .note: return DesignSystem.learning
        case .event: return DesignSystem.focus
        case .health: return DesignSystem.health
        case .insight: return DesignSystem.reflection
        }
    }

    /// Maps to legacy capture prefixes used by inbox processing.
    var legacyPrefix: String {
        switch self {
        case .task: return "Task"
        case .note: return "Idea"
        case .event: return "Reminder"
        case .health: return "Health"
        case .insight: return "Insight"
        }
    }
}

struct ExecutiveCaptureSheet: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss
    @State private var activeEntry: CaptureMenuType?

    let userId: String
    var onOpenInbox: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            DesignSystem.backgroundPrimary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    Text("Capture")
                        .textStyleScreenTitle()
                    Text("Quick capture anything.")
                        .textStyleBody(color: DesignSystem.textSecondary)
                }
                .padding(.top, DesignSystem.spacingXL)

                VStack(spacing: DesignSystem.spacingMD) {
                    ForEach(CaptureMenuType.allCases) { type in
                        LACaptureTypeRow(
                            title: type.rawValue,
                            subtitle: type.subtitle,
                            icon: type.icon,
                            iconColor: type.iconColor
                        ) {
                            HapticManager.impact(.light)
                            activeEntry = type
                        }
                    }
                }

                inboxFooterLink

                Spacer(minLength: 80)
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)

            LADismissFAB {
                dismiss()
            }
            .padding(.bottom, DesignSystem.spacingXXXL)
        }
        .sheet(item: $activeEntry) { type in
            CaptureEntrySheet(type: type, userId: userId) {
                dismiss()
            }
            .environmentObject(shell)
        }
        .accessibilityIdentifier("screen-capture")
    }

    private var inboxFooterLink: some View {
        Button(action: onOpenInbox) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: "tray.full")
                    .font(.dsIcon())
                Text("View inbox")
                    .textStyleCardTitle()
                if shell.inboxVM.unprocessedCount > 0 {
                    Text("\(shell.inboxVM.unprocessedCount)")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.accentOnPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DesignSystem.accentPrimary))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
            }
            .foregroundColor(DesignSystem.textPrimary)
            .padding(.horizontal, DesignSystem.spacingMD)
            .padding(.vertical, DesignSystem.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                    .fill(DesignSystem.backgroundElevated)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-view-inbox")
    }
}

private struct CaptureEntrySheet: View {
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechManager = SpeechRecognitionManager()

    let type: CaptureMenuType
    let userId: String
    let onSaved: () -> Void

    @State private var text = ""
    @State private var mood: Double = 0.5
    @State private var eventDate = Date()
    @State private var confirmation: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.backgroundPrimary.ignoresSafeArea()

                if let confirmation {
                    Text(confirmation)
                        .textStyleScreenTitle()
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                dismiss()
                                onSaved()
                            }
                        }
                } else {
                    entryContent
                }
            }
            .navigationTitle(type.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if type != .health {
                    isFocused = true
                }
            }
            .onChange(of: speechManager.transcript) { _, transcript in
                guard !transcript.isEmpty else { return }
                text = transcript
            }
            .keyboardDismissToolbar(label: "Done")
        }
    }

    @ViewBuilder
    private var entryContent: some View {
        VStack(spacing: DesignSystem.spacingLG) {
            switch type {
            case .health:
                VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                    Text("How are you feeling?")
                        .textStyleSectionLabel()
                    Slider(value: $mood, in: 0...1)
                    Text(moodLabel)
                        .textStyleCaption()
                }
                .padding(.horizontal, DesignSystem.screenHorizontal)
            case .event:
                DatePicker("When", selection: $eventDate)
                    .datePickerStyle(.compact)
                    .padding(.horizontal, DesignSystem.screenHorizontal)
            default:
                EmptyView()
            }

            TextField(entryPlaceholder, text: $text, axis: .vertical)
                .lineLimit(type == .health ? 2...4 : 1...8)
                .focused($isFocused)
                .textStyleBody()
                .padding(.horizontal, DesignSystem.screenHorizontal)

            HStack(spacing: DesignSystem.spacingHero) {
                Button(action: toggleVoice) {
                    Image(systemName: speechManager.isListening ? "waveform.circle.fill" : "mic.circle")
                        .font(.dsIconLarge())
                        .foregroundColor(speechManager.isListening ? DesignSystem.focus : DesignSystem.textMuted)
                }
                .accessibilityLabel("Speak")
                Spacer()
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)

            Spacer()
        }
        .padding(.top, DesignSystem.spacingLG)
    }

    private var entryPlaceholder: String {
        switch type {
        case .task: return "What needs doing?"
        case .note: return "What's on your mind?"
        case .event: return "Event title"
        case .health: return "Optional note"
        case .insight: return "What did you notice?"
        }
    }

    private var moodLabel: String {
        switch mood {
        case ..<0.33: return "Low"
        case ..<0.66: return "Okay"
        default: return "Good"
        }
    }

    private var canSave: Bool {
        if type == .health { return true }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isFocused = false
        KeyboardDismiss.dismiss()
        HapticManager.notification(.success)

        var payload = "[\(type.legacyPrefix)] "
        switch type {
        case .health:
            payload += "Mood: \(moodLabel)"
            if !trimmed.isEmpty { payload += " — \(trimmed)" }
        case .event:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let when = formatter.string(from: eventDate)
            payload += trimmed.isEmpty ? "Event at \(when)" : "\(trimmed) @ \(when)"
        default:
            guard !trimmed.isEmpty else { return }
            payload += trimmed
        }

        shell.contextOrchestrator.captureNote(payload, userId: userId)
        Task {
            await shell.inboxVM.captureAndProcess(text: payload)
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
