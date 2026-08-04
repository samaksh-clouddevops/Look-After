import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Minimal bottom affordance — expands to a dynamically sized planning conversation (up to 60% of screen).
struct ExecutiveAssistantSheet: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    @ObservedObject var speechManager: SpeechRecognitionManager
    @ObservedObject var speechSynthesizer: PlanningSpeechSynthesizer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var onSubmit: (_ text: String, _ startedWithVoice: Bool) -> Void
    var onNegotiationSelect: (String) -> Void
    var onRedesignWithAI: (String) -> Void = { _ in }

    @State private var isExpanded = false
    @State private var dragTranslation: CGFloat = 0
    @State private var intrinsicSheetHeight: CGFloat = 136

    private let collapsedHeight: CGFloat = 52
    private let maxExpandedFraction: CGFloat = 0.60
    private let minExpandedHeight: CGFloat = 136
    private let dragHandleBlockHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let maxExpandedHeight = geo.size.height * maxExpandedFraction
            let naturalExpandedHeight = max(intrinsicSheetHeight, minExpandedHeight)
            let targetExpandedHeight = min(naturalExpandedHeight, maxExpandedHeight)
            let atScrollCap = naturalExpandedHeight > maxExpandedHeight
            let panelMaxHeight = atScrollCap ? (maxExpandedHeight - dragHandleBlockHeight) : nil
            let currentHeight = isExpanded
                ? max(collapsedHeight, targetExpandedHeight + dragTranslation)
                : collapsedHeight

            ZStack(alignment: .bottom) {
                if isExpanded {
                    DesignSystem.shadowElevated.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { collapse() }
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sheetBody(
                        maxExpandedHeight: maxExpandedHeight,
                        panelMaxHeight: panelMaxHeight,
                        currentHeight: currentHeight
                    )
                }
            }
            .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: isExpanded)
            .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: intrinsicSheetHeight)
            .overlay(alignment: .bottom) {
                if isExpanded {
                    heightMeasurementProbe
                        .frame(width: geo.size.width)
                        .hidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
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
        .onChange(of: planningVM.turns.count) { _, _ in
            if !planningVM.turns.isEmpty, !isExpanded { expand() }
        }
        .accessibilityIdentifier("screen-assistant-sheet")
    }

    @ViewBuilder
    private func sheetBody(
        maxExpandedHeight: CGFloat,
        panelMaxHeight: CGFloat?,
        currentHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            if isExpanded {
                dragHandle
                conversationView(maxPanelHeight: panelMaxHeight)
            } else {
                collapsedAffordance
            }
        }
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous))
        .shadow(color: DesignSystem.shadowElevated, radius: isExpanded ? 16 : 8, y: -2)
        .frame(height: currentHeight, alignment: .top)
        .gesture(expandedDragGesture(maxExpandedHeight: maxExpandedHeight))
    }

    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
            .fill(DesignSystem.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
    }

    private var collapsedAffordance: some View {
        Button(action: expand) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                Text("Replan or adjust my day")
                    .font(.dsCaption(weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DesignSystem.textMuted)
            }
            .padding(.horizontal, DesignSystem.screenHorizontal)
            .padding(.vertical, DesignSystem.spacingMD)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Replan or adjust my day")
        .featureTourAnchor(.todayAssistant, cornerRadius: DesignSystem.radiusLG)
        .id(AppFeatureTourAnchorID.todayAssistant.rawValue)
    }

    private var dragHandle: some View {
        Capsule()
            .fill(DesignSystem.divider)
            .frame(width: 36, height: 4)
            .padding(.top, DesignSystem.spacingSM)
            .padding(.bottom, DesignSystem.spacingXS)
            .accessibilityHidden(true)
    }

    private var heightMeasurementProbe: some View {
        VStack(spacing: 0) {
            dragHandle
            conversationView(maxPanelHeight: nil)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SheetIntrinsicHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetIntrinsicHeightKey.self) { height in
            guard height > 0 else { return }
            intrinsicSheetHeight = height
        }
    }

    private func conversationView(maxPanelHeight: CGFloat?) -> some View {
        ExecutivePlanningConversationView(
            planningVM: planningVM,
            speechManager: speechManager,
            speechSynthesizer: speechSynthesizer,
            isExpanded: true,
            maxPanelHeight: maxPanelHeight,
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

    private func expandedDragGesture(maxExpandedHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard isExpanded else { return }
                dragTranslation = max(0, value.translation.height)
            }
            .onEnded { value in
                guard isExpanded else { return }
                let threshold = maxExpandedHeight * 0.22
                if value.translation.height > threshold || value.predictedEndTranslation.height > threshold {
                    collapse()
                } else {
                    withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                        dragTranslation = 0
                    }
                }
            }
    }

    private func expand() {
        HapticManager.impact(.light)
        dragTranslation = 0
        isExpanded = true
    }

    private func collapse() {
        HapticManager.impact(.light)
        speechManager.stopListening()
        isExpanded = false
        dragTranslation = 0
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

private struct SheetIntrinsicHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum ExecutiveAssistantMetrics {
    static let collapsedHeight: CGFloat = 52
    static let collapsedBottomPadding: CGFloat = collapsedHeight + 8
}
