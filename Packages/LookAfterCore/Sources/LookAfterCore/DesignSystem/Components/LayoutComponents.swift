import SwiftUI

/// Horizontal scroll filter chip bar.
public struct FilterChipBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    public init(items: [Item], selection: Binding<Item>, title: @escaping (Item) -> String) {
        self.items = items
        self._selection = selection
        self.title = title
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.spacingSM) {
                ForEach(items, id: \.self) { item in
                    FilterChipView(
                        title: title(item),
                        isSelected: selection == item
                    ) {
                        selection = item
                    }
                }
            }
            .padding(.horizontal, DesignSystem.spacingLG)
        }
    }
}

public struct FilterChipView: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dsChip())
                .dsChipText()
                .foregroundColor(isSelected ? DesignSystem.backgroundPrimary : DesignSystem.textMuted)
                .padding(.horizontal, DesignSystem.spacingMD)
                .padding(.vertical, DesignSystem.spacingSM)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? DesignSystem.accentPrimary : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .minTouchTarget(36)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public struct PriorityBadgeView: View {
    let priority: Priority

    public init(priority: Priority) {
        self.priority = priority
    }

    public var body: some View {
        Image(systemName: priority.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color(hex: priority.colorHex))
            .minTouchTarget(32)
            .accessibilityLabel("\(priority.label) priority")
    }
}

public struct SectionHeaderView: View {
    let title: String
    var icon: String?
    var iconGradient: LinearGradient

    public init(title: String, icon: String? = nil, iconGradient: LinearGradient = DesignSystem.accentGradient) {
        self.title = title
        self.icon = icon
        self.iconGradient = iconGradient
    }

    public var body: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconGradient)
            }

            Text(title)
                .font(.dsHeadline())
                .foregroundColor(DesignSystem.textPrimary)
                .dsPrimaryText(lineLimit: 1)

            Spacer(minLength: 0)
        }
    }
}

/// General-purpose elevated card container for all modules.
public struct CardContainerView<Content: View>: View {
    let title: String
    var icon: String?
    var iconGradient: LinearGradient
    var compact: Bool
    @ViewBuilder let content: Content

    public init(
        title: String,
        icon: String? = nil,
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

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? DesignSystem.spacingSM : DesignSystem.spacingMD) {
            SectionHeaderView(title: title, icon: icon, iconGradient: iconGradient)
            content
        }
        .elevatedSurface(
            padding: compact ? DesignSystem.spacingMD : DesignSystem.cardPaddingMin,
            emphasis: .standard,
            cornerRadius: DesignSystem.radiusLG
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
