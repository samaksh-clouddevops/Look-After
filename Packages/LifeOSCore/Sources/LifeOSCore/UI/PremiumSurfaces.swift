import SwiftUI

// MARK: - Surface emphasis

public enum SurfaceEmphasis {
    case standard
    case prominent
    case subtle
}

// MARK: - Elevated surface

public struct ElevatedSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var emphasis: SurfaceEmphasis
    var cornerRadius: CGFloat?

    public init(
        padding: CGFloat = DesignSystem.spacingXL,
        emphasis: SurfaceEmphasis = .standard,
        cornerRadius: CGFloat? = nil
    ) {
        self.padding = padding
        self.emphasis = emphasis
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceBackground)
            .overlay(
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? (emphasis == .prominent ? DesignSystem.radiusHero : DesignSystem.radiusSurface)
    }

    private var strokeOpacity: Double {
        emphasis == .prominent ? 0.06 : 0.04
    }

    private var shadowColor: Color {
        emphasis == .subtle ? .clear : DesignSystem.shadowElevated.opacity(emphasis == .prominent ? 1 : 0.6)
    }

    private var shadowRadius: CGFloat {
        emphasis == .prominent ? DesignSystem.shadowRadius : 10
    }

    private var shadowY: CGFloat {
        emphasis == .prominent ? DesignSystem.shadowYOffset : 4
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                    .fill(fillColor)
            )
    }

    private var fillColor: Color {
        switch emphasis {
        case .prominent: return DesignSystem.backgroundElevated.opacity(0.72)
        case .standard: return DesignSystem.backgroundElevated.opacity(0.5)
        case .subtle: return DesignSystem.backgroundSecondary.opacity(0.35)
        }
    }
}

public extension View {
    func elevatedSurface(
        padding: CGFloat = DesignSystem.spacingXL,
        emphasis: SurfaceEmphasis = .standard,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        modifier(ElevatedSurfaceModifier(padding: padding, emphasis: emphasis, cornerRadius: cornerRadius))
    }
}

public struct ElevatedSurface<Content: View>: View {
    var padding: CGFloat
    var emphasis: SurfaceEmphasis
    let content: Content

    public init(
        padding: CGFloat = DesignSystem.spacingXL,
        emphasis: SurfaceEmphasis = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.emphasis = emphasis
        self.content = content()
    }

    public var body: some View {
        content.elevatedSurface(padding: padding, emphasis: emphasis)
    }
}

// MARK: - Destination tile (NavigationLink label)

public struct DestinationTile: View {
    let title: String
    var subtitle: String?
    var badge: String?
    var emphasis: SurfaceEmphasis

    public init(title: String, subtitle: String? = nil, badge: String? = nil, emphasis: SurfaceEmphasis = .standard) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.emphasis = emphasis
    }

    public var body: some View {
        HStack(spacing: DesignSystem.spacingLG) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let badge {
                TagChipView(badge, style: .neutral)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
        }
        .padding(DesignSystem.spacingLG)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusSurface, style: .continuous)
                .fill(emphasis == .prominent ? DesignSystem.backgroundElevated.opacity(0.72) : DesignSystem.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusSurface, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - Destination card (button)

public struct DestinationCard: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    public init(title: String, subtitle: String, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            DestinationTile(title: title, subtitle: subtitle)
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Hero content block

public struct PremiumHeroBlock: View {
    let meta: String?
    let title: String
    let subtitle: String?
    var duration: String?

    public init(meta: String? = nil, title: String, subtitle: String? = nil, duration: String? = nil) {
        self.meta = meta
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            if let meta, !meta.isEmpty {
                Text(meta.uppercased())
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                    .tracking(0.6)
            }

            Text(title)
                .font(.dsTitle())
                .foregroundColor(DesignSystem.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let duration, !duration.isEmpty {
                Text(duration)
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
