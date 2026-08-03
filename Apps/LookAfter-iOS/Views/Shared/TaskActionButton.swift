import SwiftUI
import LookAfterCore

/// Uniform task action button with a 44pt minimum touch target.
struct TaskActionButton: View {
    enum Style {
        case primary
        case secondary
        case destructive
    }

    let title: String
    let icon: String
    let style: Style
    let isDisabled: Bool
    let action: () -> Void

    init(
        title: String,
        icon: String,
        style: Style = .secondary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .foregroundColor(foregroundColor)
                .background(background)
                .overlay(border)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return DesignSystem.accentPrimary
        case .destructive: return DesignSystem.error
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                .fill(DesignSystem.accentGradient)
        case .secondary:
            RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                .fill(Color.white.opacity(0.06))
        case .destructive:
            RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                .fill(DesignSystem.error.opacity(0.12))
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .primary:
            EmptyView()
        case .secondary:
            RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                .stroke(DesignSystem.accentPrimary.opacity(0.45), lineWidth: 1)
        case .destructive:
            RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                .stroke(DesignSystem.error.opacity(0.45), lineWidth: 1)
        }
    }
}

/// Layout metrics shared by tests and previews.
enum TaskActionButtonMetrics {
    static let minHeight: CGFloat = DesignSystem.minTouchTarget
    static let cornerRadius: CGFloat = DesignSystem.radiusSM
    static let horizontalPadding: CGFloat = DesignSystem.spacingMD
    static let iconSize: CGFloat = 14
}
