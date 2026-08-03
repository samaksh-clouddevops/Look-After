import SwiftUI

// MARK: - Conversation card (Brain / Coach — no chat bubbles)

public struct LAConversationCard: View {
    let title: String?
    let bodyText: String
    var footnote: String?
    var isUser: Bool

    public init(
        title: String? = nil,
        bodyText: String,
        footnote: String? = nil,
        isUser: Bool = false
    ) {
        self.title = title
        self.bodyText = bodyText
        self.footnote = footnote
        self.isUser = isUser
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.dsCaption(weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }

            Text(bodyText)
                .font(.dsBody())
                .foregroundColor(DesignSystem.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.dsMetadata())
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .padding(DesignSystem.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(isUser ? DesignSystem.accentPrimary.opacity(0.12) : DesignSystem.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isUser ? .isStaticText : .isSummaryElement)
    }
}

// MARK: - Timeline row (Apple Calendar aesthetic)

public struct LATimelineRow: View {
    let timeLabel: String
    let title: String
    var subtitle: String?
    var icon: String?
    var isCurrent: Bool
    var isCompleted: Bool

    public init(
        timeLabel: String,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        isCurrent: Bool = false,
        isCompleted: Bool = false
    ) {
        self.timeLabel = timeLabel
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isCurrent = isCurrent
        self.isCompleted = isCompleted
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingMD) {
            Text(timeLabel)
                .font(.dsMetadata(weight: .semibold))
                .foregroundColor(isCurrent ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                .frame(width: 56, alignment: .trailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DesignSystem.spacingXS) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    Text(title)
                        .font(.dsBody(weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(isCompleted ? DesignSystem.textMuted : DesignSystem.textPrimary)
                        .strikethrough(isCompleted)
                        .lineLimit(2)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, DesignSystem.spacingSM)
            .padding(.horizontal, DesignSystem.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .fill(isCurrent ? DesignSystem.accentPrimary.opacity(0.08) : DesignSystem.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .stroke(isCurrent ? DesignSystem.accentPrimary.opacity(0.25) : DesignSystem.divider, lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timeLabel), \(title)")
        .accessibilityAddTraits(isCompleted ? .isStaticText : [])
    }
}

// MARK: - Bottom sheet scaffold

public struct LABottomSheet<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DesignSystem.divider)
                .frame(width: 36, height: 4)
                .padding(.top, DesignSystem.spacingSM)
                .padding(.bottom, DesignSystem.spacingMD)
                .accessibilityHidden(true)

            if let title {
                Text(title)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignSystem.screenHorizontal)
                    .padding(.bottom, DesignSystem.spacingMD)
            }

            content
        }
        .background(DesignSystem.backgroundPrimary)
    }
}
