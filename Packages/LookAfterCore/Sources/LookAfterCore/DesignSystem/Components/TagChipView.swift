import SwiftUI

/// Single-line capsule tag used for metadata, filters, and status.
public struct TagChipView: View {
    public enum Style {
        case neutral
        case accent
        case tinted(Color)
        case status(Color)
    }

    let title: String
    var icon: String?
    var style: Style

    public init(_ title: String, icon: String? = nil, style: Style = .neutral) {
        self.title = title
        self.icon = icon
        self.style = style
    }

    public var body: some View {
        HStack(spacing: DesignSystem.spacingXS) {
            if let icon, !icon.isEmpty {
                Image(systemName: icon)
                    .font(.dsChip())
            }
            Text(title)
                .font(.dsChip())
                .dsChipText()
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, DesignSystem.spacingSM + 2)
        .padding(.vertical, DesignSystem.spacingXS + 2)
        .background(Capsule(style: .continuous).fill(backgroundColor))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        switch style {
        case .neutral: return DesignSystem.textMuted
        case .accent: return DesignSystem.accentPrimary
        case .tinted: return DesignSystem.textSecondary
        case .status: return DesignSystem.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral: return Color.white.opacity(0.06)
        case .accent: return DesignSystem.accentGlow
        case .tinted: return Color.white.opacity(0.06)
        case .status(let color): return color.opacity(0.85)
        }
    }
}

/// Wrapping row of metadata chips — prevents vertical letter stacking.
public struct MetadataTagRow: View {
    let tags: [TagChipView]

    public init(tags: [TagChipView]) {
        self.tags = tags
    }

    public init(@TagBuilder content: () -> [TagChipView]) {
        self.tags = content()
    }

    public var body: some View {
        FlowLayout(horizontalSpacing: DesignSystem.spacingSM, verticalSpacing: DesignSystem.spacingSM) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                tag
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@resultBuilder
public enum TagBuilder {
    public static func buildBlock(_ components: TagChipView...) -> [TagChipView] {
        components
    }

    public static func buildOptional(_ component: [TagChipView]?) -> [TagChipView] {
        component ?? []
    }

    public static func buildEither(first: [TagChipView]) -> [TagChipView] { first }
    public static func buildEither(second: [TagChipView]) -> [TagChipView] { second }

    public static func buildArray(_ components: [[TagChipView]]) -> [TagChipView] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: TagChipView) -> [TagChipView] {
        [expression]
    }

    public static func buildExpression(_ expression: TagChipView?) -> [TagChipView] {
        expression.map { [$0] } ?? []
    }
}

public extension LifeTask {
    /// One-line metadata for compact task rows.
    var compactMetadataLine: String? {
        var parts: [String] = []
        parts.append("Estimated time \(estimatedMinutes) min")

        if isRecurring {
            parts.append(recurrenceRule.rawValue)
        }
        if isFixedTimeEvent {
            if let start = scheduledTime {
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                parts.append(formatter.string(from: start))
            } else {
                parts.append("Fixed")
            }
        }
        if isOverdue {
            parts.append("Overdue")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Standard metadata chips for task cards.
    func metadataTags(timeLabel: String? = nil) -> [TagChipView] {
        var tags: [TagChipView] = [
            TagChipView(lifeArea.rawValue, icon: lifeArea.icon, style: .neutral),
            TagChipView(timeLabel ?? "Estimated time \(estimatedMinutes) min")
        ]
        if isRecurring {
            tags.append(TagChipView(recurrenceRule.rawValue, icon: "repeat", style: .accent))
        }
        if isFixedTimeEvent {
            tags.append(TagChipView("Fixed time", icon: "lock.fill", style: .accent))
        }
        if isOverdue {
            tags.append(TagChipView("OVERDUE", style: .status(DesignSystem.error)))
        }
        return tags
    }
}
