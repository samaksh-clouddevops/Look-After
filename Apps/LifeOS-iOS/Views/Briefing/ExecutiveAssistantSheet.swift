import SwiftUI
import LifeOSCore
import LifeOSFeatures

/// Collapsible Executive Assistant — Apple Maps-style bottom sheet over the timeline.
struct ExecutiveAssistantSheet: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    @ObservedObject var speechManager: SpeechRecognitionManager
    @ObservedObject var speechSynthesizer: PlanningSpeechSynthesizer

    var onSubmit: (_ text: String, _ startedWithVoice: Bool) -> Void
    var onNegotiationSelect: (String) -> Void
    var onRedesignWithAI: (String) -> Void = { _ in }

    @State private var isExpanded = false
    @State private var dragTranslation: CGFloat = 0
    @State private var collapseFieldFocused = false
    @FocusState private var expandedFieldFocused: Bool

    private let collapsedHeight: CGFloat = 80
    private let expandedFraction: CGFloat = 0.72

    var body: some View {
        GeometryReader { geo in
            let expandedHeight = geo.size.height * expandedFraction
            let currentHeight = isExpanded
                ? max(collapsedHeight, expandedHeight + dragTranslation)
                : collapsedHeight

            ZStack(alignment: .bottom) {
                if isExpanded {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { collapse() }
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sheetBody(expandedHeight: expandedHeight)
                        .frame(height: currentHeight)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isExpanded)
            .animation(.interactiveSpring(), value: dragTranslation)
        }
        .onChange(of: planningVM.isProcessing) { _, processing in
            if processing { expand() }
        }
        .onChange(of: planningVM.isProcessing) { wasProcessing, processing in
            guard wasProcessing, !processing else { return }
            scheduleAutoCollapse()
        }
        .onChange(of: planningVM.isReplanning) { wasReplanning, replanning in
            if replanning { expand() }
            if wasReplanning, !replanning { scheduleAutoCollapse() }
        }
        .onChange(of: planningVM.draftText) { _, text in
            if !text.isEmpty, !isExpanded { expand() }
        }
    }

    // MARK: - Sheet body

    @ViewBuilder
    private func sheetBody(expandedHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            if isExpanded {
                dragHandle
            }

            if isExpanded {
                expandedContent
            } else {
                collapsedBar
            }
        }
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusXL, style: .continuous))
        .shadow(color: .black.opacity(isExpanded ? 0.35 : 0.2), radius: isExpanded ? 24 : 12, y: -4)
        .gesture(expandedDragGesture(expandedHeight: expandedHeight))
    }

    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusXL, style: .continuous)
            .fill(DesignSystem.backgroundElevated)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusXL, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    // MARK: - Collapsed (default)

    private var collapsedBar: some View {
        Button {
            expand()
        } label: {
            HStack(spacing: DesignSystem.spacingMD) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DesignSystem.accentGradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan With Me")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                    Text("Executive Assistant")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.textSecondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Tell me what's changed…")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textMuted)
                        .lineLimit(1)

                    HStack(spacing: DesignSystem.spacingSM) {
                        collapsedMicButton
                        Text("Type or Speak")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
            .padding(.vertical, DesignSystem.spacingMD)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Plan with me, executive assistant")
    }

    private var collapsedMicButton: some View {
        Button {
            expand()
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await speechManager.startListening()
                planningVM.setInputMode(.voice)
            }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.backgroundPrimary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DesignSystem.accentPrimary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Speak to executive assistant")
    }

    // MARK: - Expanded

    private var dragHandle: some View {
        VStack(spacing: DesignSystem.spacingSM) {
            Capsule()
                .fill(DesignSystem.textMuted.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, DesignSystem.spacingSM)

            HStack {
                Spacer()
                Button {
                    collapse()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                        Text("Collapse")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(DesignSystem.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DesignSystem.backgroundPrimary.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
        }
    }

    private var expandedContent: some View {
        ExecutivePlanningConversationView(
            planningVM: planningVM,
            speechManager: speechManager,
            speechSynthesizer: speechSynthesizer,
            isExpanded: true,
            onSubmit: { text, voice in
                if !isExpanded { expand() }
                onSubmit(text, voice)
            },
            onNegotiationSelect: onNegotiationSelect,
            onRedesignWithAI: onRedesignWithAI,
            onExpand: { expand() },
            onStartVoice: {
                expand()
                planningVM.setInputMode(.voice)
            },
            onStartTyping: { expand() }
        )
    }

    // MARK: - Gestures

    private func expandedDragGesture(expandedHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard isExpanded else { return }
                dragTranslation = max(0, value.translation.height)
            }
            .onEnded { value in
                guard isExpanded else { return }
                let threshold = expandedHeight * 0.22
                if value.translation.height > threshold || value.predictedEndTranslation.height > threshold {
                    collapse()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        dragTranslation = 0
                    }
                }
            }
    }

    // MARK: - State

    private func expand() {
        HapticManager.impact(.light)
        dragTranslation = 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            isExpanded = true
        }
    }

    private func collapse() {
        HapticManager.impact(.light)
        expandedFieldFocused = false
        speechManager.stopListening()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            isExpanded = false
            dragTranslation = 0
        }
    }

    private func scheduleAutoCollapse() {
        guard planningVM.negotiation == nil else { return }
        guard !planningVM.turns.contains(where: \.offersAIRedesign) else { return }
        Task {
            if planningVM.inputMode == .voice {
                try? await Task.sleep(nanoseconds: 800_000_000)
                while speechSynthesizer.isSpeaking {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            } else {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            await MainActor.run {
                if !planningVM.isProcessing, !planningVM.isReplanning, planningVM.negotiation == nil {
                    collapse()
                }
            }
        }
    }
}

/// Bottom inset height for timeline content above the collapsed assistant bar.
enum ExecutiveAssistantMetrics {
    static let collapsedHeight: CGFloat = 80
    static let collapsedBottomPadding: CGFloat = collapsedHeight + 8
}
