import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Executive Planning conversation content — shown inside the expanded assistant sheet.
struct ExecutivePlanningConversationView: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    @ObservedObject var speechManager: SpeechRecognitionManager
    @ObservedObject var speechSynthesizer: PlanningSpeechSynthesizer

    var isExpanded: Bool = false
    /// When set, caps panel height and scrolls the middle section once content exceeds it.
    var maxPanelHeight: CGFloat?
    var onSubmit: (_ text: String, _ startedWithVoice: Bool) -> Void
    var onNegotiationSelect: (String) -> Void
    var onRedesignWithAI: (String) -> Void = { _ in }
    var onExpand: () -> Void = {}
    var onStartVoice: () -> Void = {}
    var onStartTyping: () -> Void = {}

    @State private var showTextFallback = false
    @FocusState private var textFieldFocused: Bool

    private var mode: PlanningInputMode {
        planningVM.inputMode ?? .text
    }

    private var isVoiceLocked: Bool {
        planningVM.inputMode == .voice
    }

    private var isTextLocked: Bool {
        planningVM.inputMode == .text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            panelHeader
            scrollableMiddleSection
            inputArea
        }
        .frame(maxHeight: maxPanelHeight, alignment: .top)
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .padding(.bottom, DesignSystem.spacingSM)
        .keyboardDismissToolbar(label: "Send", onDone: submitText)
        .accessibilityIdentifier("screen-planning-conversation")
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: DesignSystem.spacingSM) {
                Text("🧠")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan With Me")
                        .font(.dsHeadline())
                        .foregroundColor(DesignSystem.textPrimary)
                    Text("Executive Assistant")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                }
            }

            Spacer()

            if planningVM.inputMode != nil {
                modalityToggle
            }
        }
    }

    private var modalityToggle: some View {
        HStack(spacing: 4) {
            modalityButton(.text, icon: "keyboard", label: "Text")
            modalityButton(.voice, icon: "waveform", label: "Voice")
        }
        .padding(3)
        .background(Capsule().fill(DesignSystem.backgroundPrimary.opacity(0.6)))
    }

    private func modalityButton(_ target: PlanningInputMode, icon: String, label: String) -> some View {
        let selected = mode == target
        return Button(action: {
            HapticManager.impact(.light)
            planningVM.setInputMode(target)
            if target == .text { showTextFallback = true }
        }, label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(selected ? DesignSystem.backgroundPrimary : DesignSystem.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? DesignSystem.accentPrimary : Color.clear))
        })
        .buttonStyle(.plain)
    }

    // MARK: - Reasoning pipeline

    private var reasoningPipeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(planningVM.thinkingSteps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: DesignSystem.spacingSM) {
                    Image(systemName: stepIcon(for: index))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(stepColor(for: index))
                        .frame(width: 14)
                    Text(step)
                        .font(.dsCaption())
                        .foregroundColor(index <= currentStepIndex ? DesignSystem.textPrimary : DesignSystem.textMuted)
                }
            }
        }
        .padding(.vertical, DesignSystem.spacingXS)
    }

    private var currentStepIndex: Int {
        guard let visible = planningVM.visibleThinkingStep,
              let idx = planningVM.thinkingSteps.firstIndex(of: visible) else {
            return planningVM.thinkingSteps.count - 1
        }
        return idx
    }

    private func stepIcon(for index: Int) -> String {
        index < currentStepIndex ? "checkmark.circle.fill" : (index == currentStepIndex ? "circle.dotted" : "circle")
    }

    private func stepColor(for index: Int) -> Color {
        index <= currentStepIndex ? DesignSystem.accentPrimary : DesignSystem.textMuted
    }

    // MARK: - Conversation

    private var hasConversationTurns: Bool {
        !planningVM.turns.isEmpty || planningVM.isProcessing
    }

    @ViewBuilder
    private var scrollableMiddleSection: some View {
        let middle = middleSection

        if let cap = middleScrollMaxHeight {
            ScrollViewReader { proxy in
                ViewThatFits(in: .vertical) {
                    middle
                    ScrollView(.vertical, showsIndicators: true) {
                        middle
                    }
                    .frame(maxHeight: cap)
                }
                .onChange(of: planningVM.turns.count) { _, _ in
                    scrollToLatestTurn(using: proxy)
                }
                .onChange(of: planningVM.isProcessing) { _, _ in
                    scrollToLatestTurn(using: proxy)
                }
            }
        } else {
            middle
        }
    }

    private var middleSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            if planningVM.isProcessing, !planningVM.thinkingSteps.isEmpty {
                reasoningPipeline
            }

            if hasConversationTurns {
                conversationStack
            }

            if let negotiation = planningVM.negotiation {
                negotiationStrip(negotiation, action: onNegotiationSelect)
            }

            if let multiDayPlanning = planningVM.multiDayPlanning {
                negotiationStrip(multiDayPlanning, action: onNegotiationSelect)
            }

            if planningVM.turns.isEmpty && !planningVM.isProcessing {
                quickStartChips
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var middleScrollMaxHeight: CGFloat? {
        guard let maxPanelHeight else { return nil }
        let chromeReserve: CGFloat = planningVM.inputMode == .voice ? 228 : 168
        return max(72, maxPanelHeight - chromeReserve)
    }

    private var conversationStack: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            ForEach(planningVM.turns) { turn in
                turnEntry(turn)
                    .id(turn.id)
            }

            if planningVM.isProcessing {
                HStack(spacing: DesignSystem.spacingSM) {
                    ProgressView().scaleEffect(0.85)
                    Text(planningVM.visibleThinkingStep ?? "Updating your day…")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                }
            }
        }
        .padding(.vertical, DesignSystem.spacingXS)
    }

    private func scrollToLatestTurn(using proxy: ScrollViewProxy) {
        guard let last = planningVM.turns.last else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    @ViewBuilder
    private func turnEntry(_ turn: PlanningConversationTurn) -> some View {
        switch turn.role {
        case .user:
            VStack(alignment: .leading, spacing: 2) {
                Text("YOU")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DesignSystem.textMuted)
                    .tracking(0.8)
                Text(turn.text)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
                    .italic()
            }
        case .assistant:
            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                Text(turn.text)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if turn.id == planningVM.turns.last(where: { $0.role == .assistant })?.id,
                   let draft = planningVM.multiDayDraft {
                    MultiDayPlanPreviewCard(draft: draft)
                }

                if turn.offersAIRedesign, let message = turn.sourceUserMessage {
                    redesignWithAIButton(userMessage: message)
                }
            }
            .padding(.vertical, DesignSystem.spacingXS)
        case .system:
            EmptyView()
        }
    }

    // MARK: - AI redesign

    private func redesignWithAIButton(userMessage: String) -> some View {
        Button(action: {
            HapticManager.impact(.medium)
            onRedesignWithAI(userMessage)
        }, label: {
            HStack(spacing: DesignSystem.spacingSM) {
                if planningVM.isRedesigningWithAI {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(planningVM.isRedesigningWithAI ? "Redesigning with AI…" : "Redesign with AI")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(DesignSystem.accentPrimary)
            .padding(.horizontal, DesignSystem.spacingMD)
            .padding(.vertical, DesignSystem.spacingSM)
            .background(
                Capsule()
                    .fill(DesignSystem.accentPrimary.opacity(0.12))
                    .overlay(Capsule().stroke(DesignSystem.accentPrimary.opacity(0.35)))
            )
        })
        .buttonStyle(.plain)
        .disabled(planningVM.isProcessing || planningVM.isRedesigningWithAI)
    }

    // MARK: - Negotiation

    private func negotiationStrip(_ negotiation: PlanningNegotiation, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text(negotiation.question)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.spacingSM) {
                    ForEach(negotiation.options, id: \.self) { option in
                        Button(option) {
                            HapticManager.impact(.medium)
                            action(option)
                        }
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textPrimary)
                        .padding(.horizontal, DesignSystem.spacingMD)
                        .padding(.vertical, DesignSystem.spacingSM)
                        .background(
                            Capsule()
                                .fill(DesignSystem.accentPrimary.opacity(0.12))
                                .overlay(Capsule().stroke(DesignSystem.accentPrimary.opacity(0.35)))
                        )
                    }
                }
            }
        }
    }

    private var quickStartChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.spacingSM) {
                ForEach(quickStartSuggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        HapticManager.impact(.light)
                        planningVM.draftText = suggestion
                        onSubmit(suggestion, false)
                    }
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textSecondary)
                    .padding(.horizontal, DesignSystem.spacingMD)
                    .padding(.vertical, DesignSystem.spacingSM)
                    .background(Capsule().fill(DesignSystem.backgroundPrimary.opacity(0.5)))
                }
            }
        }
    }

    private var quickStartSuggestions: [String] {
        [
            "Plan something over several days",
            "Break a big goal into daily steps",
            "Spread work across the week"
        ]
    }

    // MARK: - Input

    @ViewBuilder
    private var inputArea: some View {
        if isVoiceLocked && !showTextFallback {
            voicePrimaryInput
        } else if isTextLocked {
            textPrimaryInput
        } else {
            neutralInput
        }
    }

    private var voicePrimaryInput: some View {
        VStack(spacing: DesignSystem.spacingSM) {
            if speechManager.isListening {
                AudioWaveformView(levels: speechManager.audioLevels)
                if !speechManager.transcript.isEmpty {
                    Text(speechManager.transcript)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if speechSynthesizer.isSpeaking {
                HStack(spacing: DesignSystem.spacingSM) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(DesignSystem.accentPrimary)
                    Text("Speaking…")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                }
            }

            HStack {
                Spacer()
                Button(action: {
                    HapticManager.impact(.medium)
                    Task {
                        if speechManager.isListening {
                            speechManager.stopListening()
                            let transcript = speechManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !transcript.isEmpty {
                                onSubmit(transcript, true)
                            }
                        } else {
                            speechSynthesizer.stop()
                            onStartVoice()
                            await speechManager.startListening()
                        }
                    }
                }, label: {
                    ZStack {
                        Circle()
                            .fill(speechManager.isListening ? Color.red.opacity(0.85) : DesignSystem.accentPrimary)
                            .frame(width: 52, height: 52)
                        Image(systemName: speechManager.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DesignSystem.backgroundPrimary)
                    }
                })
                .buttonStyle(.plain)
                Spacer()
            }

            Button("Type instead") {
                showTextFallback = true
                planningVM.setInputMode(.text)
            }
            .font(.dsCaption())
            .foregroundColor(DesignSystem.textSecondary)
        }
    }

    private var textPrimaryInput: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            TextField("What's happening in your life today?", text: $planningVM.draftText, axis: .vertical)
                .font(.dsBody())
                .foregroundColor(DesignSystem.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .tint(DesignSystem.textSecondary)
                .focused($textFieldFocused)
                .onSubmit { submitText() }
                .onTapGesture { onStartTyping() }

            if !planningVM.draftText.isEmpty {
                PremiumIconButton("arrow.up.circle.fill", isActive: true, action: submitText)
            }
        }
    }

    private var neutralInput: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            PremiumIconButton(speechManager.isListening ? "stop.circle.fill" : "mic.fill") {
                HapticManager.impact(.medium)
                onStartVoice()
                Task {
                    if speechManager.isListening {
                        speechManager.stopListening()
                        let transcript = speechManager.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !transcript.isEmpty {
                            onSubmit(transcript, true)
                        }
                    } else {
                        planningVM.setInputMode(.voice)
                        await speechManager.startListening()
                    }
                }
            }

            TextField("Speak or type what's happening today…", text: $planningVM.draftText, axis: .vertical)
                .font(.dsBody())
                .foregroundColor(DesignSystem.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .tint(DesignSystem.textSecondary)
                .focused($textFieldFocused)
                .onSubmit { submitText() }
                .onTapGesture { onStartTyping() }

            if !planningVM.draftText.isEmpty {
                PremiumIconButton("arrow.up.circle.fill", isActive: true, action: submitText)
            }
        }
    }

    private func submitText() {
        let text = planningVM.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if planningVM.inputMode == nil {
            planningVM.setInputMode(.text)
        }
        textFieldFocused = false
        KeyboardDismiss.dismiss()
        onSubmit(text, false)
    }
}

// MARK: - Multi-day preview card

private struct MultiDayPlanPreviewCard: View {
    let draft: MultiDayPlanDraft

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack {
                Text(draft.title)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                Spacer()
                Text("\(draft.dayCount) days")
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.accentPrimary)
            }

            if let deadline = draft.deadline {
                Text("Deadline: \(deadline.formatted(date: .abbreviated, time: .omitted))")
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textSecondary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.slices.sorted { $0.dayIndex < $1.dayIndex }) { slice in
                        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                            Text("Day \(slice.dayIndex + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(DesignSystem.textMuted)
                                .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slice.title)
                                    .font(.dsCaption())
                                    .foregroundColor(DesignSystem.textPrimary)
                                HStack(spacing: 6) {
                                    if let window = slice.windowLabel {
                                        Text(window)
                                    }
                                    Text("\(slice.estimatedMinutes)m")
                                }
                                .font(.system(size: 10))
                                .foregroundColor(DesignSystem.textSecondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 140)

            if !draft.reasoning.isEmpty {
                Text(draft.reasoning)
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textSecondary)
            }
        }
        .padding(DesignSystem.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DesignSystem.accentPrimary.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignSystem.accentPrimary.opacity(0.2)))
        )
    }
}
