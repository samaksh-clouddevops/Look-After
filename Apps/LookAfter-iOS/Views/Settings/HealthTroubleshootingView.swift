import SwiftUI
import LookAfterCore
import LookAfterHealth
import LookAfterFeatures

/// In-app help for Apple Watch / Health data — plain language, live status, common fixes.
struct HealthTroubleshootingView: View {
    @ObservedObject var healthSync: HealthSyncService
    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss

    let userId: String

    @State private var expandedSituationID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                howItWorksSection

                if let status = healthSync.connectionStatus {
                    HealthStatusBanner(
                        status: status,
                        style: .full,
                        onPrimaryAction: { handlePrimaryAction(status.primaryAction) }
                    )
                }

                if let lastSync = healthSync.lastSyncDate {
                    HStack {
                        Text("Last synced")
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.textMuted)
                        Spacer()
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    .padding(.horizontal, DesignSystem.spacingMD)
                }

                commonSituationsSection

                Button(action: runCheckAgain) {
                    Label("Run check again", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(healthSync.isSyncing)

                if let report = healthSync.verificationReport {
                    HealthVerificationReportView(report: report)
                }
            }
            .padding(DesignSystem.spacingLG)
        }
        .background(DesignSystem.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Help with Watch data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            healthSync.refreshConnectionStatus(userId: userId, healthSummary: shell.brainVM.healthSummary)
        }
        .accessibilityIdentifier("screen-health-troubleshooting")
    }

    // MARK: - Sections

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text("How it works")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)

            flowStep(number: 1, icon: "applewatch", text: "Your Apple Watch records sleep, steps, and heart rate.")
            flowStep(number: 2, icon: "heart.text.square.fill", text: "Data syncs to the Health app on your iPhone.")
            flowStep(number: 3, icon: "sparkles", text: "\(UserFacingCopy.productName) reads from Health — it never pairs with your Watch directly.")
        }
        .padding(DesignSystem.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
    }

    private var commonSituationsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text("Common situations")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)

            ForEach(situations) { situation in
                situationRow(situation)
            }
        }
    }

    private func flowStep(number: Int, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            ZStack {
                Circle()
                    .fill(DesignSystem.accentPrimary.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(DesignSystem.accentPrimary)
            }
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.textMuted)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func situationRow(_ situation: HealthSituation) -> some View {
        let isExpanded = expandedSituationID == situation.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSituationID = isExpanded ? nil : situation.id
                }
            } label: {
                HStack {
                    Text(situation.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                }
                .padding(DesignSystem.spacingMD)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(situation.explanation)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(situation.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.textMuted)
                            Text(step)
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.spacingMD)
                .padding(.bottom, DesignSystem.spacingMD)
            }

            Divider().opacity(0.3)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.backgroundSecondary.opacity(0.6))
        )
    }

    // MARK: - Actions

    private func handlePrimaryAction(_ action: HealthStatusAction) {
        HealthStatusActionHandler.perform(
            action,
            onConnect: { /* connect handled via Settings or parent */ },
            onSync: runCheckAgain,
            onOpenSettings: { /* user is already in settings flow */ }
        )
    }

    private func runCheckAgain() {
        Task {
            await healthSync.syncHealthData(userId: userId)
            healthSync.refreshConnectionStatus(userId: userId, healthSummary: shell.brainVM.healthSummary)
        }
    }

    // MARK: - Content

    private var situations: [HealthSituation] {
        [
            HealthSituation(
                id: "connected-no-sleep",
                title: "I connected but sleep still shows —",
                explanation: "Look After can read Health, but there may not be sleep data in the iPhone Health app yet.",
                steps: [
                    "Wear your Apple Watch overnight with Sleep tracking enabled.",
                    "Open the Health app and confirm last night's sleep appears.",
                    "Return here and tap Run check again."
                ]
            ),
            HealthSituation(
                id: "steps-not-sleep",
                title: "Steps work but sleep doesn't",
                explanation: "Some permissions or sleep tracking may still be off. iOS doesn't tell apps which category was denied.",
                steps: [
                    "Open Health → Sharing → Apps → \(UserFacingCopy.productName).",
                    "Turn on Sleep as well as Steps and Heart Rate.",
                    "Wear your Watch overnight, then tap Run check again."
                ]
            ),
            HealthSituation(
                id: "denied-permission",
                title: "I denied permission by accident",
                explanation: "You can re-enable access in the Health app without reinstalling Look After.",
                steps: [
                    "Open the Health app on your iPhone.",
                    "Tap Sharing → Apps → \(UserFacingCopy.productName).",
                    "Turn on Sleep, Steps, and Heart Rate.",
                    "Tap Run check again here."
                ]
            ),
            HealthSituation(
                id: "no-watch",
                title: "I don't have an Apple Watch",
                explanation: "Look After still works with iPhone-only Health data — steps from your phone, manual sleep entries, and third-party apps.",
                steps: [
                    "Connect Apple Health and allow the categories you use.",
                    "Log sleep manually in Health, or use another sleep app that writes to Health.",
                    "Tap Run check again after data appears in Health."
                ]
            ),
            HealthSituation(
                id: "health-has-data",
                title: "Data in Health app but not Look After",
                explanation: "Usually a sync or permission refresh fixes this.",
                steps: [
                    "Confirm Sleep, Steps, and Heart Rate are enabled for \(UserFacingCopy.productName) in Health → Sharing → Apps.",
                    "Tap Run check again to pull the latest data.",
                    "If data still doesn't appear, contact support — this may be a bug."
                ]
            ),
        ]
    }
}

private struct HealthSituation: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let steps: [String]
}
