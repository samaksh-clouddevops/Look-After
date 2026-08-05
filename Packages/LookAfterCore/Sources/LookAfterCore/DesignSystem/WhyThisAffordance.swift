import SwiftUI

// MARK: - Why now? (collapsed transparency)

/// Collapsed explanation affordance for AI recommendations — never clutters the default view.
public struct WhyThisAffordance: View {
    let reasons: [String]
    let contextLine: String?
    let durationLabel: String?
    let insights: [RecommendationInsight]
    var onOpenInsight: ((RecommendationInsight) -> Void)?

    @State private var isExpanded = false

    public init(
        reasons: [String],
        contextLine: String? = nil,
        durationLabel: String? = nil,
        insights: [RecommendationInsight] = [],
        onOpenInsight: ((RecommendationInsight) -> Void)? = nil
    ) {
        self.reasons = reasons
        self.contextLine = contextLine
        self.durationLabel = durationLabel
        self.insights = insights
        self.onOpenInsight = onOpenInsight
    }

    private var hasContent: Bool {
        !allReasons.isEmpty || !(durationLabel?.isEmpty ?? true) || !insights.isEmpty
    }

    private var allReasons: [String] {
        var lines: [String] = []
        if let contextLine, !contextLine.isEmpty { lines.append(contextLine) }
        lines.append(contentsOf: reasons.filter { !$0.isEmpty })
        return lines
    }

    public var body: some View {
        if hasContent {
            VStack(spacing: 12) {
                Button(action: {
                    isExpanded.toggle()
                }, label: {
                    Text(isExpanded ? "Hide" : "Why now?")
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                })
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(allReasons, id: \.self) { reason in
                            Text(reason)
                                .font(.dsCaption())
                                .foregroundColor(DesignSystem.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let durationLabel, !durationLabel.isEmpty {
                            Text(durationLabel)
                                .font(.dsMetadata())
                                .foregroundColor(DesignSystem.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ForEach(insights) { insight in
                            insightBlock(insight)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func insightBlock(_ insight: RecommendationInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.headline)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textPrimary)
            Text(insight.detail)
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textMuted)
            if insight.destination != .none, let onOpenInsight {
                Button(action: { onOpenInsight(insight) }) {
                    Text(insight.sourceLabel)
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.accentPrimary)
                }
                .buttonStyle(.plain)
            } else if !insight.sourceLabel.isEmpty {
                Text(insight.sourceLabel)
                    .font(.dsMetadata())
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
