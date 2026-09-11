import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Surfaces life commitments that haven't shown up lately.
struct LifeGapsCard: View {
    let gaps: [LifeGap]
    var onOpenTimeline: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    Text("Easy to overlook")
                        .textStyleSectionLabel()

                    Text("These haven't been logged lately.")
                        .textStyleCaption()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(gaps.prefix(3)) { gap in
                        gapCard(gap)
                    }
                }

                Button(action: onOpenTimeline) {
                    HStack(spacing: DesignSystem.spacingXS) {
                        Text("Open today's plan")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.accentPrimary)
            }
        }
    }

    private func gapCard(_ gap: LifeGap) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            Circle()
                .fill(gap.severity == .important ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                Text(gap.message)
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(gap.suggestedAction)
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DesignSystem.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.contentSurfaceElevated)
                .shadow(
                    color: DesignSystem.shadowElevated.opacity(DesignSystem.shadowOpacity(for: colorScheme) * 0.5),
                    radius: 8,
                    x: 0,
                    y: 3
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
    }
}
