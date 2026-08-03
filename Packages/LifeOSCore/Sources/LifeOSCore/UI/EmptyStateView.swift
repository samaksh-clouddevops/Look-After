import SwiftUI

/// A reusable empty state view for modules with no data.
public struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    
    public init(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.onAction = onAction
    }
    
    public var body: some View {
        VStack(spacing: DesignSystem.spacingXL) {
            Spacer(minLength: 0)
            
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DesignSystem.textMuted)
                .padding(.bottom, DesignSystem.spacingXS)
                .accessibilityHidden(true)
            
            Text(title)
                .font(.dsTitle())
                .foregroundColor(DesignSystem.textPrimary)
                .multilineTextAlignment(.center)
                .dsPrimaryText(lineLimit: 3)
            
            Text(subtitle)
                .font(.dsBody())
                .foregroundColor(DesignSystem.textMuted)
                .multilineTextAlignment(.center)
                .dsPrimaryText(lineLimit: 4)
                .padding(.horizontal, DesignSystem.spacingXXXL)
            
            if let actionTitle, let onAction {
                Button(action: onAction) {
                    HStack(spacing: DesignSystem.spacingSM) {
                        Image(systemName: "plus.circle.fill")
                        Text(actionTitle)
                    }
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
                .padding(.horizontal, DesignSystem.spacingXXXL)
                .padding(.top, DesignSystem.spacingSM)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
