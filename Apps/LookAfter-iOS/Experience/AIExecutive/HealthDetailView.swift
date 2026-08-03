import SwiftUI
import LookAfterCore
import LookAfterFeatures

struct HealthDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shell: AppShellState

    var body: some View {
        ZStack {
            DesignSystem.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.spacingLG) {
                    if let summary = shell.brainVM.healthSummary {
                        sleepHeroCard(summary)
                        metricsGrid(summary)
                    } else {
                        Text("Connect Apple Health to see recovery metrics.")
                            .font(.dsSecondary())
                            .foregroundColor(DesignSystem.textSecondary)
                            .padding(.top, DesignSystem.spacingHero)
                    }
                }
                .padding(DesignSystem.screenHorizontal)
                .padding(.top, DesignSystem.spacingXL)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(DesignSystem.textMuted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close health detail")
                }
                Spacer()
            }
            .padding(.horizontal, DesignSystem.spacingMD)
        }
        .accessibilityIdentifier("screen-health-detail")
    }

    private func sleepHeroCard(_ summary: HealthSummary) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text("Last night")
                .font(.dsCaption(weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
                .textCase(.uppercase)

            Text(formatMinutes(summary.totalSleepMinutes))
                .font(.dsDisplay())
                .foregroundColor(DesignSystem.textPrimary)

            Text("Sleep duration")
                .font(.dsSecondary())
                .foregroundColor(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.cardPaddingMin)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
    }

    private func metricsGrid(_ summary: HealthSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingMD) {
            metricCard(title: "Deep", value: formatMinutes(summary.deepSleepMinutes), icon: "moon.zzz.fill")
            metricCard(title: "REM", value: formatMinutes(summary.remSleepMinutes), icon: "brain.head.profile")
            if let hrv = summary.hrvAverage {
                metricCard(title: "HRV", value: "\(Int(hrv)) ms", icon: "waveform.path.ecg")
            }
            if let steps = summary.stepCount {
                metricCard(title: "Steps", value: "\(steps)", icon: "figure.walk")
            }
        }
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Label(title, systemImage: icon)
                .font(.dsCaption(weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
            Text(value)
                .font(.dsHeadline())
                .foregroundColor(DesignSystem.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func formatMinutes(_ minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }
}
