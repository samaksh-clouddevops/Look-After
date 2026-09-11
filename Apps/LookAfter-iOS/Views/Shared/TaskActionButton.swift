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
                        .tint(progressTint)
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
            .frame(minHeight: DesignSystem.minTouchTarget)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .modifier(TaskActionButtonChrome(style: style))
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled && !isLoading ? 0.55 : 1)
        .accessibilityLabel(isLoading ? "Loading" : title)
    }

    private var progressTint: Color {
        switch style {
        case .primary: return DesignSystem.accentOnPrimary
        case .secondary: return DesignSystem.accentPrimary
        case .destructive: return DesignSystem.error
        }
    }
}

private struct TaskActionButtonChrome: ViewModifier {
    let style: TaskActionButton.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content
                .buttonStyle(.glassProminent)
                .tint(LookAfterChrome.accentTint)
        case .secondary:
            content
                .foregroundColor(DesignSystem.accentPrimary)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                        .fill(DesignSystem.contentSurfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                        .stroke(DesignSystem.accentPrimary.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous))
                .buttonStyle(.plain)
        case .destructive:
            content
                .foregroundColor(DesignSystem.error)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                        .fill(DesignSystem.contentSurfaceSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                        .stroke(DesignSystem.error.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous))
                .buttonStyle(.plain)
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
