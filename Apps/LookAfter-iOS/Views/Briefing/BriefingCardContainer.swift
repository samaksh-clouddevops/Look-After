import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Reusable glass card wrapper for Daily Briefing sections.
struct BriefingCardContainer<Content: View>: View {
    let title: String
    let icon: String
    let iconGradient: LinearGradient
    var compact: Bool = false
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String,
        iconGradient: LinearGradient = DesignSystem.accentGradient,
        compact: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconGradient = iconGradient
        self.compact = compact
        self.content = content()
    }

    var body: some View {
        CardContainerView(
            title: title,
            icon: icon,
            iconGradient: iconGradient,
            compact: compact
        ) {
            content
        }
    }
}

/// Simple horizontal bar chart for weekly trend mini-cards.
struct BriefingMiniChart: View {
    let points: [BriefingTrendPoint]
    let color: Color
    var maxValue: Double?

    private var ceiling: Double {
        if let maxValue { return max(maxValue, 1) }
        return max(points.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.spacingXS) {
            ForEach(points) { point in
                VStack(spacing: DesignSystem.spacingXS) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(point.value > 0 ? 0.9 : 0.2))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 4)
                        .frame(height: max(4, CGFloat(point.value / ceiling) * 48))

                    Text(point.label)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textMuted)
                        .dsChipText()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 64)
        .accessibilityLabel("Trend chart")
    }
}
