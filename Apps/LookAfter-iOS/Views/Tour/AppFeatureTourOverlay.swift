import SwiftUI
import LookAfterCore

/// Adaptive guided-tour overlay: layout-aware card, spotlight, and arrow.
struct AppFeatureTourOverlay: View {
    @ObservedObject var coordinator: AppFeatureTourCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusTourCard: Bool

    @State private var measuredCardSize: CGSize = CGSize(width: 320, height: 220)

    var body: some View {
        GeometryReader { geo in
            let proposal = coordinator.layoutProposal
            let localCard = localCardFrame(proposal: proposal, in: geo)

            ZStack(alignment: .topLeading) {
                spotlightLayer(proposal: proposal, container: geo)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)

                // Absorb taps outside the card (modal coach behavior).
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .allowsHitTesting(!coordinator.currentStep.allowsTargetInteraction)

                cardStack(localFrame: localCard, proposal: proposal)
                    .position(
                        x: localCard.midX,
                        y: localCard.midY
                    )
            }
            .onAppear {
                publishChrome(geo: geo)
                focusTourCard = true
            }
            .onChange(of: geo.size) { _, _ in
                publishChrome(geo: geo)
            }
            .onChange(of: geo.safeAreaInsets) { _, _ in
                publishChrome(geo: geo)
            }
            .onChange(of: coordinator.stepIndex) { _, _ in
                focusTourCard = true
                publishChrome(geo: geo)
            }
            .onChange(of: measuredCardSize) { _, size in
                coordinator.updateLayoutChrome(
                    screenBounds: globalScreenBounds(from: geo),
                    safeArea: geo.safeAreaInsets,
                    cardSize: size
                )
            }
            .onChange(of: dynamicTypeSize) { _, _ in
                publishChrome(geo: geo)
            }
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityIdentifier("screen-feature-tour")
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Spotlight

    @ViewBuilder
    private func spotlightLayer(proposal: TourLayoutProposal?, container: GeometryProxy) -> some View {
        let highlight = proposal?.highlightFrame ?? coordinator.highlightFrame()
        let radius = coordinator.currentHighlightCornerRadius
        let localHighlight = highlight.map { globalToLocal($0, in: container) }

        ZStack {
            if let localHighlight, localHighlight.isValidObstacle {
                SpotlightCutoutShape(highlight: localHighlight, cornerRadius: radius)
                    .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: localHighlight)

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

    // MARK: - Card + arrow

    private func cardStack(localFrame: CGRect, proposal: TourLayoutProposal?) -> some View {
        VStack(spacing: 0) {
            if proposal?.arrowEdge == .top {
                TourArrowView(edge: .top)
                    .offset(x: arrowOffsetX(localFrame: localFrame, proposal: proposal))
            }

            HStack(spacing: 0) {
                if proposal?.arrowEdge == .left {
                    TourArrowView(edge: .left)
                }

                cardContent
                    .background(
                        GeometryReader { cardGeo in
                            Color.clear.preference(
                                key: TourCardSizeKey.self,
                                value: cardGeo.size
                            )
                        }
                    )
                    .onPreferenceChange(TourCardSizeKey.self) { measuredCardSize = $0 }

                if proposal?.arrowEdge == .right {
                    TourArrowView(edge: .right)
                }
            }

            if proposal?.arrowEdge == .bottom {
                TourArrowView(edge: .bottom)
                    .offset(x: arrowOffsetX(localFrame: localFrame, proposal: proposal))
            }
        }
        .frame(width: max(localFrame.width, 1))
        .accessibilityFocused($focusTourCard)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tourAccessibilityLabel)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: localFrame)
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
                .lineLimit(3)
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
        .frame(maxWidth: DesignSystem.readableMaxWidth)
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
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: coordinator.stepIndex)
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
        // Global frame of the overlay container (full window).
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

    private func localCardFrame(proposal: TourLayoutProposal?, in geo: GeometryProxy) -> CGRect {
        let fallbackWidth = min(geo.size.width - DesignSystem.screenHorizontal * 2, 360)
        let fallbackHeight = max(measuredCardSize.height, 200)
        if let proposal {
            var local = globalToLocal(proposal.cardFrame, in: geo)
            if local.width < 1 || local.height < 1 {
                local = CGRect(
                    x: (geo.size.width - fallbackWidth) / 2,
                    y: (geo.size.height - fallbackHeight) / 2,
                    width: fallbackWidth,
                    height: fallbackHeight
                )
            }
            return local
        }
        return CGRect(
            x: (geo.size.width - fallbackWidth) / 2,
            y: (geo.size.height - fallbackHeight) / 2,
            width: fallbackWidth,
            height: fallbackHeight
        )
    }

    private func arrowOffsetX(localFrame: CGRect, proposal: TourLayoutProposal?) -> CGFloat {
        guard let proposal, proposal.arrowEdge == .top || proposal.arrowEdge == .bottom else { return 0 }
        // Convert global tip x into offset relative to card center.
        // Parent uses position at card mid; arrow is centered by default.
        let tipLocalX = proposal.arrowTip.x // global
        // Approximate using local frame mid
        return tipLocalX - (proposal.cardFrame.midX)
    }
}

// MARK: - Supporting views

private struct TourCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 { value = next }
    }
}

private struct TourArrowView: View {
    let edge: TourArrowEdge

    var body: some View {
        Triangle()
            .fill(DesignSystem.backgroundElevated)
            .frame(width: arrowSize.width, height: arrowSize.height)
            .rotationEffect(rotation)
            .accessibilityHidden(true)
    }

    private var arrowSize: CGSize {
        switch edge {
        case .top, .bottom: return CGSize(width: 18, height: 10)
        case .left, .right: return CGSize(width: 10, height: 18)
        case .none: return .zero
        }
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
