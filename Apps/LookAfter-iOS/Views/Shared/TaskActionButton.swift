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
    let isLoading: Bool
    let action: () -> Void

    init(
        title: String,
        icon: String,
        style: Style = .secondary,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(foregroundColor)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .foregroundColor(foregroundColor)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled && !isLoading ? 0.55 : 1)
        .accessibilityLabel(isLoading ? "Loading" : title)
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
    static let minHeight: CGFloat = 56
    static let cornerRadius: CGFloat = DesignSystem.radiusSM
    static let horizontalPadding: CGFloat = 6
    static let iconSize: CGFloat = 15
}
