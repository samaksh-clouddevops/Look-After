import SwiftUI
import LifeOSCore
import LifeOSData
import LifeOSFeatures

/// ADHD-friendly checklist showing exactly what Health / Apple Watch sync is doing.
struct HealthSyncProgressView: View {
    
    enum Style {
        case compact
        case full
    }
    
    @ObservedObject var healthSync: HealthSyncService
    var style: Style = .full
    
    private var headline: String {
        if let report = healthSync.verificationReport,
           healthSync.syncPhase == .complete || healthSync.syncPhase == .failed {
            return report.headline
        }
        if healthSync.syncPhase == .complete {
            return healthSync.importedMetricCount > 0 ? "Sync Complete" : "Connected — No Data Yet"
        }
        if healthSync.syncPhase == .failed {
            return "Sync Failed"
        }
        if healthSync.isConnectingForSetup {
            return "Connecting Health"
        }
        if healthSync.deferredToBackground {
            return "Connecting Health"
        }
        return "Syncing Health Data"
    }
    
    private var subtitle: String? {
        if healthSync.syncPhase == .failed, let error = healthSync.lastSyncError {
            return error
        }
        if healthSync.syncPhase == .complete {
            return healthSync.syncMessage ?? "Health data saved to ADHD Bitch"
        }
        if let setup = healthSync.setupStatusMessage {
            return setup
        }
        return healthSync.currentStepLabel
    }
    
    var body: some View {
        switch style {
        case .compact:
            compactCard
        case .full:
            fullChecklist
        }
    }
    
    // MARK: - Compact (overlay banner)
    
    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: healthSync.isConnectingForSetup ? "heart.text.square.fill" : "applewatch.watchface")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    if let label = subtitle {
                        Text(label)
                            .font(.system(size: 12, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer(minLength: 0)
                
                if healthSync.isConnectingForSetup || healthSync.isSyncing {
                    ProgressView()
                        .tint(DesignSystem.accentPrimary)
                } else if healthSync.syncPhase == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.success)
                } else if healthSync.syncPhase == .failed {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.error)
                }
            }
            
            if healthSync.isConnectingForSetup {
                Text("Usually under 5 seconds")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            } else if healthSync.totalStepCount > 0 {
                ProgressView(
                    value: Double(healthSync.completedStepCount),
                    total: Double(healthSync.totalStepCount)
                )
                .tint(DesignSystem.accentPrimary)
                
                Text("\(healthSync.completedStepCount) of \(healthSync.totalStepCount) steps done")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            }
            
            if let active = healthSync.activeStep, !healthSync.isConnectingForSetup {
                HStack(spacing: 8) {
                    Image(systemName: active.icon)
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.accentPrimary)
                    Text(active.title)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DesignSystem.accentPrimary.opacity(0.35), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Full (Settings checklist)
    
    private var fullChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundColor(DesignSystem.accentPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's happening")
                        .font(.system(size: 15, weight: .bold, design: .default))
                    if let label = healthSync.currentStepLabel {
                        Text(label)
                            .font(.system(size: 12, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }
                Spacer()
                if healthSync.isSyncing {
                    ProgressView()
                        .tint(DesignSystem.accentPrimary)
                } else if healthSync.syncPhase == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.success)
                } else if healthSync.syncPhase == .failed {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.error)
                }
            }
            
            if healthSync.canRetry {
                Button(action: {
                    healthSync.retrySync(userId: FirebaseManager.shared.currentUserId ?? "")
                }) {
                    Label("Retry Sync", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.accentPrimary)
            }
            
            if healthSync.totalStepCount > 0 {
                ProgressView(
                    value: Double(healthSync.completedStepCount),
                    total: Double(healthSync.totalStepCount)
                )
                .tint(DesignSystem.accentPrimary)
            }
            
            ForEach(healthSync.syncSteps) { step in
                stepRow(step)
            }

            if let report = healthSync.verificationReport {
                HealthVerificationReportView(report: report)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func stepRow(_ step: HealthSyncStepItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(for: step.status)
                .frame(width: 22, height: 22)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(step.status == .pending ? DesignSystem.textMuted : DesignSystem.textPrimary)
                
                Text(step.detail ?? step.explanation)
                    .font(.system(size: 11, design: .default))
                    .foregroundColor(detailColor(for: step.status))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .animation(.easeInOut(duration: 0.2), value: step.status)
    }
    
    @ViewBuilder
    private func statusIcon(for status: HealthSyncStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(DesignSystem.textMuted.opacity(0.5))
        case .active:
            ProgressView()
                .scaleEffect(0.85)
                .tint(DesignSystem.accentPrimary)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DesignSystem.success)
        case .noData:
            Image(systemName: "minus.circle.fill")
                .foregroundColor(DesignSystem.warning)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(DesignSystem.error)
        }
    }
    
    private func detailColor(for status: HealthSyncStepStatus) -> Color {
        switch status {
        case .pending: return DesignSystem.textMuted
        case .active: return DesignSystem.accentPrimary
        case .done: return DesignSystem.textSecondary
        case .noData: return DesignSystem.warning.opacity(0.9)
        case .failed: return DesignSystem.error.opacity(0.9)
        }
    }
}

/// Presents HealthKit authorization from a sheet so the system dialog appears above the app UI.
struct HealthConnectSheet: View {
    @ObservedObject var healthSync: HealthSyncService
    let userId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shell: AppShellState
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                    Text("Apple Health will ask which data ADHD Bitch can read. Turn on Sleep, Steps, and Heart Rate for the best plan.")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if userId.isEmpty {
                        Label("Sign in first, then try again.", systemImage: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DesignSystem.warning)
                    } else {
                        HealthSyncProgressView(healthSync: healthSync, style: .full)

                        if healthSync.syncPhase == .failed, healthSync.verificationReport == nil {
                            Button {
                                Task { await runConnect() }
                            } label: {
                                Label("Retry Connection", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.accentPrimary)
                        } else if healthSync.syncPhase == .complete,
                                  let report = healthSync.verificationReport,
                                  !report.hasUsableData {
                            Button {
                                Task { await runConnect() }
                            } label: {
                                Label("Retry After Fixing Issues", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.accentPrimary)
                        }
                    }
                }
                .padding(DesignSystem.spacingLG)
            }
            .navigationTitle("Connect Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                guard !didStart, !userId.isEmpty else { return }
                didStart = true
                await runConnect()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func runConnect() async {
        let resolvedId = FirebaseManager.shared.resolvedUserId.isEmpty ? userId : FirebaseManager.shared.resolvedUserId
        guard !resolvedId.isEmpty else { return }

        await healthSync.connectHealthDuringSetup(
            userId: resolvedId,
            forceAuthorizationPrompt: true
        )
        guard healthSync.syncPhase == .complete else { return }
        await shell.refreshContext(
            userId: resolvedId,
            userName: UserLifeProfileStore.resolvedDisplayName(),
            peakStartHour: UserLifeProfileStore.load().peakStartHour
        )
        shell.refreshWidgetData()
    }
}

// MARK: - Verification report UI

struct HealthVerificationReportView: View {
    let report: HealthSyncVerificationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: report.overallPassed && report.hasUsableData ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundColor(report.hasUsableData ? DesignSystem.success : DesignSystem.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verification")
                        .font(.system(size: 15, weight: .bold))
                    Text(report.headline)
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.textSecondary)
                }
                Spacer()
            }

            Text(report.summary)
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(report.checks) { check in
                verificationRow(check)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var borderColor: Color {
        if report.hasUsableData && report.overallPassed { return DesignSystem.success }
        if report.hasUsableData { return DesignSystem.warning }
        return DesignSystem.error
    }

    private func verificationRow(_ check: HealthVerificationCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            outcomeIcon(check.status)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: check.icon)
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                    Text(check.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                }

                if let value = check.value {
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.success)
                }

                if let issue = check.issue {
                    Text(issue)
                        .font(.system(size: 11))
                        .foregroundColor(issueColor(check.status))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let fix = check.fixHint {
                    Text("Fix: \(fix)")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func outcomeIcon(_ status: HealthVerificationOutcome) -> some View {
        switch status {
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DesignSystem.success)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DesignSystem.warning)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(DesignSystem.error)
        }
    }

    private func issueColor(_ status: HealthVerificationOutcome) -> Color {
        switch status {
        case .passed: return DesignSystem.textSecondary
        case .warning: return DesignSystem.warning.opacity(0.95)
        case .failed: return DesignSystem.error.opacity(0.95)
        }
    }
}
