import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Sectional AI insights from tasks, health, habits, and other modules.
struct BriefingModuleInsightsCard: View {
    let insights: [BriefingModuleInsight]
    var isLoading: Bool

    var body: some View {
        BriefingChapterSection(
            title: "From your life",
            subtitle: "Small notes pulled together for today",
            icon: "text.quote"
        ) {
            if isLoading, insights.isEmpty {
                HStack(spacing: DesignSystem.spacingSM) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Pulling insights together…")
                        .textStyleCaption()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DesignSystem.spacingSM)
            } else if insights.isEmpty {
                Text("Nothing specific yet — add a task or connect health and this fills in.")
                    .textStyleCaption()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(insights) { insight in
                        insightRow(insight)
                    }
                }
            }
        }
        .accessibilityIdentifier("briefing-module-insights")
    }

    private func insightRow(_ insight: BriefingModuleInsight) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            Image.safeSystemName(insight.icon, fallback: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.accentPrimary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.module.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.textMuted)

                Text(insight.message)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.contentSurfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
    }
}
