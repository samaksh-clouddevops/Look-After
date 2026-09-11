import SwiftUI
import LookAfterCore

/// ADHD Quick-Dock pinned at the bottom of the Master Canvas for zero-friction emergency assistance.
public struct ADHDFloatingDockView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var onDecideForMe: () -> Void
    var onVoiceCapture: () -> Void
    var onResetMode: () -> Void

    public init(
        onDecideForMe: @escaping () -> Void,
        onVoiceCapture: @escaping () -> Void,
        onResetMode: @escaping () -> Void
    ) {
        self.onDecideForMe = onDecideForMe
        self.onVoiceCapture = onVoiceCapture
        self.onResetMode = onResetMode
    }

    public var body: some View {
        GlassEffectContainer(spacing: DesignSystem.spacingSM) {
            HStack(spacing: DesignSystem.spacingSM) {
                PremiumCompactButton("Decide", icon: "bolt.shield.fill", role: .secondary) {
                    HapticManager.impact(.heavy)
                    onDecideForMe()
                }

                Button {
                    HapticManager.impact(.medium)
                    onVoiceCapture()
                } label: {
                    Label("Voice", systemImage: "mic.fill")
                        .font(.dsCaption(weight: .semibold))
                        .padding(.horizontal, DesignSystem.spacingSM)
                        .frame(minHeight: DesignSystem.minTouchTarget)
                }
                .buttonStyle(.glassProminent)
                .tint(LookAfterChrome.accentTint)

                PremiumCompactButton("Reset", icon: "heart.flow.fill", role: .tertiary) {
                    HapticManager.impact(.soft)
                    onResetMode()
                }
            }
            .padding(.horizontal, DesignSystem.spacingMD)
            .padding(.vertical, DesignSystem.spacingSM)
            .modifier(ADHDDockChrome(reduceTransparency: reduceTransparency))
        }
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .accessibilityIdentifier("screen-adhd-dock")
    }
}

private struct ADHDDockChrome: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignSystem.contentSurfaceElevated)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DesignSystem.border, lineWidth: 1)
                )
        } else {
            content
                .glassEffect(.regular, in: .capsule)
        }
    }
}
