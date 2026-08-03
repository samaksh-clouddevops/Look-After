import SwiftUI

// MARK: - Shared button chrome

private enum PremiumButtonMetrics {
    static let minHeight: CGFloat = 52
    static let horizontalPadding: CGFloat = 24
    static let verticalPadding: CGFloat = 14
    static let cornerRadius: CGFloat = DesignSystem.radiusButton
}

private struct PremiumButtonLabel: View {
    let title: String
    var icon: String?
    var foreground: Color
    var allowsWrap: Bool

    init(title: String, icon: String? = nil, foreground: Color, allowsWrap: Bool = false) {
        self.title = title
        self.icon = icon
        self.foreground = foreground
        self.allowsWrap = allowsWrap
    }

    var body: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(title)
                .font(.dsHeadline())
                .lineLimit(allowsWrap ? 2 : 1)
                .minimumScaleFactor(allowsWrap ? 1 : 0.85)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: allowsWrap)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, PremiumButtonMetrics.horizontalPadding)
        .padding(.vertical, PremiumButtonMetrics.verticalPadding)
        .frame(minHeight: PremiumButtonMetrics.minHeight)
    }
}

// MARK: - Primary

public struct PremiumPrimaryButton: View {
    let title: String
    var icon: String?
    var fillsWidth: Bool
    let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        fillsWidth: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.fillsWidth = fillsWidth
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PremiumButtonLabel(title: title, icon: icon, foreground: DesignSystem.accentOnPrimary, allowsWrap: true)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusFloating, style: .continuous)
                    .fill(DesignSystem.accentPrimary)
                )
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Primary button style (for custom Button labels)

public struct PremiumPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsHeadline())
            .foregroundColor(DesignSystem.accentOnPrimary)
            .padding(.horizontal, PremiumButtonMetrics.horizontalPadding)
            .padding(.vertical, PremiumButtonMetrics.verticalPadding)
            .frame(minHeight: PremiumButtonMetrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusFloating, style: .continuous)
                    .fill(configuration.isPressed ? DesignSystem.accentPressed : DesignSystem.accentPrimary)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Secondary (ghost)

public struct PremiumGhostButton: View {
    let title: String
    var icon: String?
    var fillsWidth: Bool
    var isActive: Bool
    let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        fillsWidth: Bool = true,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.fillsWidth = fillsWidth
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            PremiumButtonLabel(
                title: title,
                icon: icon,
                foreground: isActive ? DesignSystem.accentPrimary : DesignSystem.textPrimary
            )
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: PremiumButtonMetrics.cornerRadius, style: .continuous)
                    .fill(isActive ? DesignSystem.accentGlow : DesignSystem.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PremiumButtonMetrics.cornerRadius, style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
        }
        .buttonStyle(PremiumPressStyle())
    }
}

public typealias PremiumSecondaryButton = PremiumGhostButton

// MARK: - Compact (toolbar / dock)

public struct PremiumCompactButton: View {
    let title: String
    var icon: String?
    var role: Role
    let action: () -> Void

    public enum Role {
        case primary
        case secondary
        case tertiary
    }

    public init(_ title: String, icon: String? = nil, role: Role = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.dsMetadata(weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Capsule(style: .continuous).fill(background))
        }
        .buttonStyle(PremiumPressStyle())
    }

    private var foreground: Color {
        switch role {
        case .primary: return DesignSystem.accentOnPrimary
        case .secondary: return DesignSystem.textPrimary
        case .tertiary: return DesignSystem.textSecondary
        }
    }

    private var background: Color {
        switch role {
        case .primary: return DesignSystem.accentPrimary
        case .secondary: return DesignSystem.backgroundSecondary
        case .tertiary: return DesignSystem.backgroundElevated
        }
    }
}

// MARK: - Icon button (navigation)

public struct PremiumIconButton: View {
    let icon: String
    var isActive: Bool
    let action: () -> Void

    public init(_ icon: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(isActive ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                .frame(width: DesignSystem.iconButtonSize, height: DesignSystem.iconButtonSize)
        }
        .buttonStyle(PremiumPressStyle())
    }
}

// MARK: - Toolbar cluster

public struct PremiumToolbarItem: Identifiable {
    public let id: String
    public let icon: String
    public let accessibilityLabel: String
    public let action: () -> Void

    public init(id: String, icon: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}

public struct PremiumToolbarCluster: View {
    let leading: PremiumToolbarItem?
    let items: [PremiumToolbarItem]

    public init(leading: PremiumToolbarItem? = nil, items: [PremiumToolbarItem]) {
        self.leading = leading
        self.items = items
    }

    public var body: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            if let leading {
                PremiumIconButton(leading.icon, action: leading.action)
                    .accessibilityLabel(leading.accessibilityLabel)
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                ForEach(items) { item in
                    PremiumIconButton(item.icon, action: item.action)
                        .accessibilityLabel(item.accessibilityLabel)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(Capsule(style: .continuous).fill(DesignSystem.backgroundElevated.opacity(0.55)))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .frame(minHeight: DesignSystem.minTouchTarget)
    }
}