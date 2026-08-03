import SwiftUI
import LookAfterCore
import LookAfterFeatures

struct HealthDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shell: AppShellState

    var body: some View {
        ZStack {
            SleepAtmosphereBackground()

            if let summary = shell.brainVM.healthSummary {
                VStack(spacing: 0) {
                    Spacer()

                    Text("Last night")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(DesignSystem.textSecondary.opacity(0.7))
                        .padding(.bottom, 24)

                    Text(formatMinutes(summary.totalSleepMinutes))
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(DesignSystem.textPrimary.opacity(0.85))
                        .tracking(-1)

                    Spacer().frame(height: 64)

                    VStack(spacing: 36) {
                        sleepWhisper("Deep", formatMinutes(summary.deepSleepMinutes))
                        sleepWhisper("REM", formatMinutes(summary.remSleepMinutes))
                    }
                    .padding(.horizontal, 48)

                    Spacer()
                    Spacer()
                }
            } else {
                Text("—")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(DesignSystem.textMuted.opacity(0.4))
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(DesignSystem.textMuted.opacity(0.5))
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)
                Spacer()
            }
        }
    }

    private func sleepWhisper(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.textMuted.opacity(0.45))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.textSecondary.opacity(0.6))
        }
    }

    private func formatMinutes(_ minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }
}
