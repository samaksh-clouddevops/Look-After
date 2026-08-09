import SwiftUI
import LookAfterCore

/// 60-Second Physiological Reset Breathing exercise for ADHD nervous system regulation.
public struct PhysiologicalResetView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.6
    @State private var phaseText = "Inhale Deeply..."
    @State private var secondsRemaining = 60
    /// Task-based tick — cancelled on dismiss (PERF-007); avoids orphaned Timer.publish.
    @State private var tickTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 32) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Text("60-SECOND PHYSIOLOGICAL RESET")
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(DesignSystem.textSecondary)
                    .tracking(2)

                ZStack {
                    Circle()
                        .fill(DesignSystem.accentGlow)
                        .scaleEffect(scale * 1.4)
                        .blur(radius: 30)

                    Circle()
                        .fill(DesignSystem.backgroundElevated)
                        .scaleEffect(scale)
                        .frame(width: 200, height: 200)
                        .overlay(
                            Circle()
                                .stroke(DesignSystem.accentPrimary.opacity(0.35), lineWidth: 2)
                        )

                    Text("\(secondsRemaining)s")
                        .font(.dsDisplay())
                        .foregroundColor(DesignSystem.textPrimary)
                }
                .frame(height: 260)

                Text(phaseText)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)

                Text("Double inhale through your nose, slow exhale through your mouth.")
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                PremiumPrimaryButton("I'M GROUNDED NOW") {
                    dismiss()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            startBreathingAnimation()
            startCountdown()
        }
        .onDisappear {
            tickTask?.cancel()
            tickTask = nil
        }
        .accessibilityIdentifier("screen-physiological-reset")
    }

    private func startCountdown() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled, secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                secondsRemaining -= 1
            }
            guard !Task.isCancelled else { return }
            HapticManager.notification(.success)
            dismiss()
        }
    }

    private func startBreathingAnimation() {
        guard !reduceMotion else {
            scale = 1.0
            return
        }
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            scale = 1.1
        }
    }
}
