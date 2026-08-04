import SwiftUI
import LookAfterCore

/// Adaptive guided-tour overlay: layout-aware card, spotlight, and arrow.
struct AppFeatureTourOverlay: View {
    @ObservedObject var coordinator: AppFeatureTourCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusTourCard: Bool

    @State private var measuredCardSize: CGSize = CGSize(width: 320, height: 220)

    private let arrowSize = CGSize(width: 18, height: 10)

    var body: some View {
        GeometryReader { geo in
            let proposal = coordinator.layoutProposal
            let localHighlight = highlightRect(proposal: proposal, in: geo)
            let localCard = cardRect(proposal: proposal, in: geo)

            ZStack(alignment: .topLeading) {
                spotlightLayer(localHighlight: localHighlight)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .allowsHitTesting(!coordinator.currentStep.allowsTargetInteraction)

                tourDialog(
                    localCard: localCard,
                    localHighlight: localHighlight,
                    proposal: proposal,
                    layoutWidth: cardLayoutWidth(in: geo),
                    geo: geo
                )
            }
            .onAppear {
                publishChrome(geo: geo)
                scheduleAccessibilityFocus()
            }
            .onChange(of: geo.size) { _, _ in publishChrome(geo: geo) }
            .onChange(of: coordinator.stepIndex) { _, _ in
                scheduleAccessibilityFocus()
                publishChrome(geo: geo)
            }
            .onChange(of: dynamicTypeSize) { _, _ in publishChrome(geo: geo) }
        }
        .ignoresSafeArea()
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityIdentifier("screen-feature-tour")
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Spotlight

    @ViewBuilder
    private func spotlightLayer(localHighlight: CGRect?) -> some View {
        ZStack {
            if let localHighlight, localHighlight.isValidObstacle {
                let radius = coordinator.currentHighlightCornerRadius
                SpotlightCutoutShape(highlight: localHighlight, cornerRadius: radius)
                    .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                    .compositingGroup()

                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DesignSystem.accentPrimary.opacity(0.55), lineWidth: 2)
                    .frame(width: localHighlight.width, height: localHighlight.height)
                    .position(x: localHighlight.midX, y: localHighlight.midY)
                    .allowsHitTesting(false)
            } else {
                Color.black.opacity(0.58)
            }
        }
    }

    // MARK: - Dialog (card + arrow pinned to engine rects)

    private func tourDialog(
        localCard: CGRect,
        localHighlight: CGRect?,
        proposal: TourLayoutProposal?,
        layoutWidth: CGFloat,
        geo: GeometryProxy
    ) -> some View {
        cardContent
            .frame(width: layoutWidth, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                applyMeasuredCardSize(size, geo: geo)
            }
            .overlay {
                if let proposal, proposal.arrowEdge != .none, let localHighlight {
                    arrowOverlay(
                        edge: proposal.arrowEdge,
                        cardWidth: layoutWidth,
                        localCard: localCard,
                        highlight: localHighlight
                    )
                }
            }
            .frame(width: localCard.width, alignment: .topLeading)
            .offset(x: localCard.minX, y: localCard.minY)
            .accessibilityFocused($focusTourCard)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tourAccessibilityLabel)
    }

    private func applyMeasuredCardSize(_ size: CGSize, geo: GeometryProxy) {
        guard size.width > 1, size.height > 1 else { return }
        let deltaW = abs(size.width - measuredCardSize.width)
        let deltaH = abs(size.height - measuredCardSize.height)
        guard deltaW > 2 || deltaH > 2 else { return }
        measuredCardSize = size
        Task { @MainActor in
            publishChrome(geo: geo)
        }
    }

    /// Avoid forcing AX tree sync during SwiftUI layout passes.
    private func scheduleAccessibilityFocus() {
        Task { @MainActor in
            await Task.yield()
            focusTourCard = true
        }
    }

    @ViewBuilder
    private func arrowOverlay(
        edge: TourArrowEdge,
        cardWidth: CGFloat,
        localCard: CGRect,
        highlight: CGRect
    ) -> some View {
        let targetInCardX = highlight.midX - localCard.minX
        let targetInCardY = highlight.midY - localCard.minY
        let shiftX = min(max(targetInCardX, 24), cardWidth - 24) - cardWidth / 2
        let cardHeight = max(measuredCardSize.height, localCard.height)
        let shiftY = min(max(targetInCardY, 24), max(24, cardHeight - 24)) - cardHeight / 2

        switch edge {
        case .bottom:
            TourArrowView(edge: .bottom)
                .frame(width: arrowSize.width, height: arrowSize.height)
                .offset(x: shiftX, y: arrowSize.height / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .top:
            TourArrowView(edge: .top)
                .frame(width: arrowSize.width, height: arrowSize.height)
                .offset(x: shiftX, y: -arrowSize.height / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .right:
            TourArrowView(edge: .right)
                .frame(width: arrowSize.width, height: arrowSize.height)
                .offset(x: arrowSize.width / 2, y: shiftY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        case .left:
            TourArrowView(edge: .left)
                .frame(width: arrowSize.width, height: arrowSize.height)
                .offset(x: -arrowSize.width / 2, y: shiftY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .none:
            EmptyView()
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: coordinator.currentStep.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DesignSystem.accentPrimary.opacity(0.12)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.currentStep.title)
                        .textStyleCardTitle()
                    Text(coordinator.progressLabel)
                        .textStyleCaption(color: DesignSystem.textMuted)
                }

                Spacer(minLength: 8)

                Button("Skip") {
                    HapticManager.impact(.light)
                    coordinator.skip()
                }
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textSecondary)
                .accessibilityIdentifier("tour-skip")
                .accessibilityHint("Ends the guided tour")
            }

            Text(coordinator.currentStep.message)
                .textStyleBody(color: DesignSystem.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            progressDots

            HStack(spacing: DesignSystem.spacingSM) {
                if coordinator.stepIndex > 0 {
                    Button("Back") {
                        HapticManager.impact(.light)
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            coordinator.goBack()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                    .frame(minHeight: DesignSystem.minTouchTarget)
                    .accessibilityIdentifier("tour-back")
                }

                Spacer()

                Button(coordinator.isLastStep ? "Get started" : "Next") {
                    HapticManager.impact(.medium)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        coordinator.advance()
                    }
                }
                .buttonStyle(.plain)
                .font(.dsBody(weight: .semibold))
                .foregroundColor(DesignSystem.accentOnPrimary)
                .padding(.horizontal, DesignSystem.spacingLG)
                .padding(.vertical, DesignSystem.spacingSM + 2)
                .background(Capsule(style: .continuous).fill(DesignSystem.accentPrimary))
                .frame(minHeight: DesignSystem.minTouchTarget)
                .accessibilityIdentifier(coordinator.isLastStep ? "tour-finish" : "tour-next")
            }
        }
        .padding(DesignSystem.cardPaddingMin)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundElevated)
                .shadow(color: DesignSystem.shadowElevated.opacity(0.22), radius: 24, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(coordinator.steps.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index == coordinator.stepIndex ? DesignSystem.accentPrimary : DesignSystem.border)
                    .frame(width: index == coordinator.stepIndex ? 18 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private var tourAccessibilityLabel: String {
        "\(coordinator.progressLabel). \(coordinator.currentStep.title). \(coordinator.currentStep.message)"
    }

    // MARK: - Geometry bridge

    private func publishChrome(geo: GeometryProxy) {
        coordinator.updateLayoutChrome(
            screenBounds: globalScreenBounds(from: geo),
            safeArea: geo.safeAreaInsets,
            tabBarFrame: coordinator.tabBarFrame,
            cardSize: measuredCardSize
        )
    }

    private func globalScreenBounds(from geo: GeometryProxy) -> CGRect {
        let frame = geo.frame(in: .global)
        if frame.width > 1, frame.height > 1 { return frame }
        return UIScreen.main.bounds
    }

    private func globalToLocal(_ rect: CGRect, in geo: GeometryProxy) -> CGRect {
        let origin = geo.frame(in: .global).origin
        return CGRect(
            x: rect.minX - origin.x,
            y: rect.minY - origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    private func highlightRect(proposal: TourLayoutProposal?, in geo: GeometryProxy) -> CGRect? {
        let global: CGRect?
        if let proposal, proposal.highlightFrame.isValidObstacle {
            global = proposal.highlightFrame
        } else if let padded = coordinator.highlightFrame() {
            global = padded
        } else {
            global = nil
        }
        return global.map { globalToLocal($0, in: geo) }
    }

    private func cardRect(proposal: TourLayoutProposal?, in geo: GeometryProxy) -> CGRect {
        let layoutWidth = cardLayoutWidth(in: geo)
        let fallbackHeight = max(measuredCardSize.height, 180)

        if let proposal, proposal.cardFrame.isValidObstacle {
            var local = globalToLocal(proposal.cardFrame, in: geo)
            local.size.width = layoutWidth
            if local.height < 1 {
                local.size.height = fallbackHeight
            }
            return local
        }

        let width = layoutWidth
        let height = fallbackHeight
        return CGRect(
            x: (geo.size.width - width) / 2,
            y: max(geo.safeAreaInsets.top + 12, (geo.size.height - height) / 2),
            width: width,
            height: height
        )
    }

    private func cardLayoutWidth(in geo: GeometryProxy) -> CGFloat {
        min(
            DesignSystem.readableMaxWidth,
            max(240, geo.size.width - DesignSystem.spacingMD * 2)
        )
    }
}

// MARK: - Supporting views

private struct TourArrowView: View {
    let edge: TourArrowEdge

    var body: some View {
        Triangle()
            .fill(DesignSystem.backgroundElevated)
            .overlay(
                Triangle()
                    .stroke(DesignSystem.border, lineWidth: 0.5)
            )
            .rotationEffect(rotation)
            .accessibilityHidden(true)
    }

    private var rotation: Angle {
        switch edge {
        case .top: return .degrees(0)
        case .bottom: return .degrees(180)
        case .left: return .degrees(-90)
        case .right: return .degrees(90)
        case .none: return .degrees(0)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SpotlightCutoutShape: Shape {
    let highlight: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(
            in: highlight,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return path
    }
}

#if DEBUG
struct AppFeatureTourOverlay_Previews: PreviewProvider {
    static var previews: some View {
        let coordinator = AppFeatureTourCoordinator()
        coordinator.start(force: true)
        return ZStack {
            PremiumBackground()
            AppFeatureTourOverlay(coordinator: coordinator)
        }
    }
}
#endif
