import SwiftUI

/// Shared chrome for Widget System V2 — one glance hierarchy, V4 tokens only.
public enum WidgetChrome {
    public static let padding: CGFloat = 14
    public static let gap: CGFloat = 8
    public static let gapLoose: CGFloat = 12

    public static func canvasBackground() -> some View {
        DesignSystem.backgroundPrimary
    }
}

// MARK: - Eyebrow

public struct WidgetEyebrow: View {
    public let text: String
    public let systemImage: String?
    public let tint: Color

    public init(_ text: String, systemImage: String? = nil, tint: Color = DesignSystem.textSecondary) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(text.uppercased())
                .font(.dsCaption(weight: .bold))
                .foregroundStyle(DesignSystem.textSecondary)
                .tracking(0.4)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Primary line

public struct WidgetPrimaryText: View {
    public let text: String
    public var lineLimit: Int

    public init(_ text: String, lineLimit: Int = 2) {
        self.text = text
        self.lineLimit = lineLimit
    }

    public var body: some View {
        Text(text)
            .font(.dsHeadline())
            .foregroundStyle(DesignSystem.textPrimary)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.85)
    }
}

// MARK: - Meta / why

public struct WidgetMetaText: View {
    public let text: String
    public var lineLimit: Int

    public init(_ text: String, lineLimit: Int = 2) {
        self.text = text
        self.lineLimit = lineLimit
    }

    public var body: some View {
        Text(text)
            .font(.dsMetadata())
            .foregroundStyle(DesignSystem.textMuted)
            .lineLimit(lineLimit)
    }
}

// MARK: - Energy chip (not a full background)

public struct WidgetEnergyChip: View {
    public let score: Int
    public let label: String?

    public init(score: Int, label: String? = nil) {
        self.score = max(0, min(100, score))
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("\(score)%")
                .font(.dsCaption(weight: .bold))
                .foregroundStyle(DesignSystem.accentOnPrimary)
            if let label, !label.isEmpty {
                Text(label)
                    .font(.dsCaption(weight: .semibold))
                    .foregroundStyle(DesignSystem.accentOnPrimary.opacity(0.85))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(DesignSystem.accentPrimary))
        .accessibilityLabel("Energy \(score) percent\(label.map { ", \($0)" } ?? "")")
    }
}

// MARK: - Empty / stale

public struct WidgetEmptyState: View {
    public let title: String
    public let detail: String?

    public init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WidgetChrome.gap) {
            WidgetPrimaryText(title, lineLimit: 2)
            if let detail {
                WidgetMetaText(detail)
            }
        }
    }
}

public struct WidgetStaleBanner: View {
    public var body: some View {
        Text("Open \(UserFacingCopy.productName) to refresh")
            .font(.dsCaption())
            .foregroundStyle(DesignSystem.textMuted)
    }
}

// MARK: - Root container

public struct WidgetRootContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(WidgetChrome.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                WidgetChrome.canvasBackground()
            }
    }
}
