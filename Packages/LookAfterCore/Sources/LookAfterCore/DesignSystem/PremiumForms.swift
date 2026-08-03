import SwiftUI

// MARK: - Icon styling

public extension View {
    /// Standard icon treatment — monochrome unless active (accent for selection/focus only).
    func premiumIcon(size: CGFloat = 17, active: Bool = false) -> some View {
        self
            .font(.system(size: size, weight: .regular))
            .foregroundColor(active ? DesignSystem.accentPrimary : DesignSystem.textMuted)
    }

    /// Primary action icon (add, confirm) — accent reserved for CTAs.
    func premiumActionIcon(size: CGFloat = 17) -> some View {
        premiumIcon(size: size, active: true)
    }
}

// MARK: - Text field

public struct PremiumFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .font(.dsBody())
            .foregroundColor(DesignSystem.textPrimary)
            .tint(DesignSystem.accentPrimary)
            .padding(.horizontal, DesignSystem.spacingMD)
            .padding(.vertical, DesignSystem.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .stroke(DesignSystem.divider, lineWidth: 1)
            )
    }
}

public extension TextFieldStyle where Self == PremiumFieldStyle {
    static var premium: PremiumFieldStyle { PremiumFieldStyle() }
}

// MARK: - Form wrapper

/// Drop-in replacement for `Form` — premium background, tint, and row styling.
public struct PremiumForm<Content: View>: View {
    @ViewBuilder let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Form {
            content
        }
        .listStyle(.insetGrouped)
        .premiumFormStyle()
    }
}

public extension View {
    func premiumFormStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(DesignSystem.backgroundPrimary)
            .foregroundColor(DesignSystem.textPrimary)
            .tint(DesignSystem.accentPrimary)
    }

    func premiumListRowBackground() -> some View {
        listRowBackground(DesignSystem.backgroundSecondary)
    }
}
