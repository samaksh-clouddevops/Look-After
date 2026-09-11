import SwiftUI
import LookAfterCore

/// Animated energy ring showing cognitive state — premium monochrome with lime progress.
struct EnergyRingView: View {
    let energyScore: Double
    let focusScore: Double
    let recoveryScore: Double
    let energyLevel: EnergyLevel

    @State private var animateRings = false

    var body: some View {
        ZStack {
            ringTrack(size: 140, lineWidth: 12)
            progressRing(
                size: 140,
                lineWidth: 12,
                progress: energyScore,
                tint: DesignSystem.accentPrimary
            )

            ringTrack(size: 110, lineWidth: 10)
            progressRing(
                size: 110,
                lineWidth: 10,
                progress: focusScore,
                tint: DesignSystem.textSecondary
            )

            ringTrack(size: 84, lineWidth: 8)
            progressRing(
                size: 84,
                lineWidth: 8,
                progress: recoveryScore,
                tint: DesignSystem.textMuted
            )

            VStack(spacing: 2) {
                Image(systemName: energyLevel.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)

                Text(energyLevel.rawValue)
                    .font(.dsMetadata())
                    .foregroundColor(DesignSystem.textSecondary)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.3)) {
                animateRings = true
            }
        }
    }

    private func ringTrack(size: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(DesignSystem.border, lineWidth: lineWidth)
            .frame(width: size, height: size)
    }

    private func progressRing(size: CGFloat, lineWidth: CGFloat, progress: Double, tint: Color) -> some View {
        Circle()
            .trim(from: 0, to: animateRings ? progress : 0)
            .stroke(
                tint,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-90))
    }
}

/// Legend for the energy rings.
struct EnergyRingLegend: View {
    var body: some View {
        HStack(spacing: DesignSystem.spacingLG) {
            legendItem(isAccent: true, label: "Energy")
            legendItem(isAccent: false, label: "Attention")
            legendItem(isAccent: false, label: "Recovery")
        }
    }

    private func legendItem(isAccent: Bool, label: String) -> some View {
        HStack(spacing: DesignSystem.spacingXS) {
            Circle()
                .fill(isAccent ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textMuted)
        }
    }
}

// MARK: - Previews

#Preview("Energy Ring") {
    ZStack {
        PremiumBackground()

        VStack(spacing: 20) {
            EnergyRingView(
                energyScore: 0.72,
                focusScore: 0.55,
                recoveryScore: 0.8,
                energyLevel: .high
            )

            EnergyRingLegend()
        }
    }
}
