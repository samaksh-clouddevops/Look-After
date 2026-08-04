import SwiftUI
import LookAfterCore

struct AppFeatureTourOverlay: View {
    @ObservedObject var coordinator: AppFeatureTourCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            spotlightLayer
                .ignoresSafeArea()
                .accessibilityHidden(true)

            tourCard
                .padding(.horizontal, DesignSystem.screenHorizontal)
        }
        .transition(.opacity)
        .accessibilityIdentifier("screen-feature-tour")
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Spotlight

    @ViewBuilder
    private var spotlightLayer: some View {
        if let highlight = coordinator.highlightFrame() {
            SpotlightCutoutShape(highlight: highlight, cornerRadius: 16)
                .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
        } else {
            Color.black.opacity(0.62)
        }
    }

    // MARK: - Card

    private var tourCard: some View {
        VStack(spacing: 0) {
            if coordinator.currentStep.placement == .aboveTarget {
                Spacer(minLength: cardTopInset)
            } else if coordinator.currentStep.placement == .center {
                Spacer()
            }

            cardContent

            if coordinator.currentStep.placement == .belowTarget {
                Spacer(minLength: cardBottomInset)
            } else if coordinator.currentStep.placement == .center {
                Spacer()
            }
        }
    }

    private var cardTopInset: CGFloat {
        guard let frame = coordinator.highlightFrame() else { return 120 }
        return max(DesignSystem.spacingLG, frame.minY - estimatedCardHeight - 24)
    }

    private var cardBottomInset: CGFloat {
        guard let frame = coordinator.highlightFrame() else { return 140 }
        let screenHeight = UIScreen.main.bounds.height
        return max(120, screenHeight - frame.maxY - estimatedCardHeight - 24)
    }

    private var estimatedCardHeight: CGFloat { 220 }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: coordinator.currentStep.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(DesignSystem.accentPrimary.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.currentStep.title)
                        .textStyleCardTitle()
                    Text(coordinator.progressLabel)
                        .textStyleCaption(color: DesignSystem.textMuted)
                }

                Spacer()

                Button("Skip") {
                    HapticManager.impact(.light)
                    coordinator.skip()
                }
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textSecondary)
                .accessibilityIdentifier("tour-skip")
            }

            Text(coordinator.currentStep.message)
                .textStyleBody(color: DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            progressDots

            HStack(spacing: DesignSystem.spacingSM) {
                if coordinator.stepIndex > 0 {
                    Button("Back") {
                        HapticManager.impact(.light)
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            coordinator.goBack()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                    .accessibilityIdentifier("tour-back")
                }

                Spacer()

                Button(coordinator.isLastStep ? "Get started" : "Next") {
                    HapticManager.impact(.medium)
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        coordinator.advance()
                    }
                }
                .buttonStyle(.plain)
                .font(.dsBody(weight: .semibold))
                .foregroundColor(DesignSystem.accentOnPrimary)
                .padding(.horizontal, DesignSystem.spacingLG)
                .padding(.vertical, DesignSystem.spacingSM + 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignSystem.accentPrimary)
                )
                .accessibilityIdentifier(coordinator.isLastStep ? "tour-finish" : "tour-next")
            }
        }
        .padding(DesignSystem.cardPaddingMin)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundElevated)
                .shadow(color: DesignSystem.shadowElevated.opacity(0.2), radius: 24, y: 8)
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
        .accessibilityLabel(coordinator.progressLabel)
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
