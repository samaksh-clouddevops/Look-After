import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth
import LookAfterData

struct HealthDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shell: AppShellState
    @StateObject private var healthSync = HealthSyncService.shared

    let userId: String
    var onLogMood: () -> Void = {}

    init(userId: String = "", onLogMood: @escaping () -> Void = {}) {
        self.userId = userId
        self.onLogMood = onLogMood
    }

    var body: some View {
        ZStack {
            DesignSystem.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DesignSystem.spacingLG) {
                    if let status = healthSync.connectionStatus, status.needsAttention {
                        HealthStatusBanner(
                            status: status,
                            style: .full,
                            onPrimaryAction: { handlePrimaryAction(status.primaryAction) },
                            onSeeDetails: nil
                        )
                    }

                    if let summary = shell.brainVM.healthSummary, hasVisibleMetrics(summary) {
                        sleepHeroCard(summary)
                        metricsGrid(summary)
                    } else if healthSync.connectionStatus == nil || healthSync.connectionStatus?.needsAttention != true {
                        Text("Connect Apple Health to see recovery metrics.")
                            .font(.dsSecondary())
                            .foregroundColor(DesignSystem.textSecondary)
                            .padding(.top, DesignSystem.spacingHero)
                    }

                    if let report = healthSync.verificationReport, report.hasUsableData == false || report.overallPassed == false {
                        HealthVerificationReportView(report: report)
                    }

                    actionButtons
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
        .onAppear {
            let resolvedId = resolvedUserId
            healthSync.refreshConnectionStatus(userId: resolvedId, healthSummary: shell.brainVM.healthSummary)
        }
        .accessibilityIdentifier("screen-health-detail")
    }

    private var actionButtons: some View {
        VStack(spacing: DesignSystem.spacingSM) {
            Button(action: onLogMood) {
                Label("Log how you feel", systemImage: "face.smiling")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("health-log-mood-capture")

            HStack(spacing: DesignSystem.spacingSM) {
                Button(action: syncNow) {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(healthSync.isSyncing)

                Button(action: openHealthApp) {
                    Label("Open Health", systemImage: "heart.text.square.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
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

    private func hasVisibleMetrics(_ summary: HealthSummary) -> Bool {
        (summary.totalSleepMinutes ?? 0) > 0
            || (summary.stepCount ?? 0) > 0
            || summary.hrvAverage != nil
            || summary.restingHeartRate != nil
    }

    private var resolvedUserId: String {
        if !userId.isEmpty { return userId }
        return FirebaseManager.shared.resolvedUserId
    }

    private func handlePrimaryAction(_ action: HealthStatusAction) {
        HealthStatusActionHandler.perform(
            action,
            onConnect: { /* sheet opened from connected context */ },
            onSync: syncNow,
            onOpenSettings: { dismiss() }
        )
    }

    private func syncNow() {
        let id = resolvedUserId
        guard !id.isEmpty else { return }
        Task {
            await healthSync.syncHealthData(userId: id)
            healthSync.refreshConnectionStatus(userId: id, healthSummary: shell.brainVM.healthSummary)
        }
    }

    private func openHealthApp() {
        if let url = HealthAppLinks.healthAppURL {
            UIApplication.shared.open(url)
        }
    }
}
