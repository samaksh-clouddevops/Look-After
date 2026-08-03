import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Surfaces missing life commitments on Briefing.
struct LifeGapsCard: View {
    let gaps: [LifeGap]
    var onOpenTimeline: () -> Void

    var body: some View {
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Label("What you're missing", systemImage: "exclamationmark.brain.head.profile")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(DesignSystem.textPrimary)

                Text("Your brain noticed drift from the life you're building toward.")
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textMuted)

                ForEach(gaps.prefix(3)) { gap in
                    gapRow(gap)
                }

                Button(action: onOpenTimeline) {
                    HStack {
                        Text("See today's plan")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.accentPrimary)
            }
            .padding(DesignSystem.spacingMD)
            .elevatedSurface()
        }
    }

    private func gapRow(_ gap: LifeGap) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(gap.severity == .important ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(gap.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                Text(gap.suggestedAction)
                    .font(.system(size: 12))
                    .foregroundColor(DesignSystem.textSecondary)
            }
        }
    }
}
