import SwiftUI
import LookAfterCore

/// ADHD Quick-Dock pinned at the bottom of the Master Canvas for zero-friction emergency assistance.
public struct ADHDFloatingDockView: View {

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
        HStack(spacing: DesignSystem.spacingSM) {
            PremiumCompactButton("Decide", icon: "bolt.shield.fill", role: .secondary) {
                HapticManager.impact(.heavy)
                onDecideForMe()
            }

            PremiumCompactButton("Voice", icon: "mic.fill", role: .primary) {
                HapticManager.impact(.medium)
                onVoiceCapture()
            }

            PremiumCompactButton("Reset", icon: "heart.flow.fill", role: .tertiary) {
                HapticManager.impact(.soft)
                onResetMode()
            }
        }
        .padding(.horizontal, DesignSystem.spacingMD)
        .padding(.vertical, DesignSystem.spacingSM)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .background(Capsule(style: .continuous).fill(DesignSystem.backgroundElevated.opacity(0.92)))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: DesignSystem.shadowElevated.opacity(0.5), radius: 12, x: 0, y: 6)
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .accessibilityIdentifier("screen-adhd-dock")
    }
}
