import SwiftUI
import LookAfterCore
import LookAfterFeatures

struct CycleDashboardView: View {
    @StateObject private var viewModel = CycleDashboardViewModel()
    @State private var showQuickLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !viewModel.preferences.isEnabled || !CycleFeatureGate.isEligible {
                    disabledState
                } else {
                    headerSection
                    insightSection
                    calendarStrip
                    symptomHistorySection
                    quickLogButton
                    disclaimer
                }
            }
            .padding()
        }
        .background(PremiumBackground())
        .navigationTitle("Cycle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showQuickLog) {
            CycleQuickLogSheet(viewModel: viewModel)
        }
        .onAppear { viewModel.refresh() }
        .accessibilityIdentifier("screen-cycle")
    }

    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CycleFeatureGate.isEligible ? "Cycle tracking is off" : "Cycle tracking unavailable")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
            Text(CycleFeatureGate.isEligible
                 ? "Enable cycle tracking in Settings to get phase-aware insights and logging."
                 : "Cycle tracking is available when you identify as female. Update your profile in Settings if needed.")
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    private var headerSection: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    .frame(width: 88, height: 88)
                Circle()
                    .trim(from: 0, to: phaseProgress)
                    .stroke(DesignSystem.accentPrimary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 88, height: 88)
                VStack(spacing: 2) {
                    if let day = viewModel.snapshot.cycleDay {
                        Text("Day \(day)")
                            .font(.system(size: 18, weight: .bold))
                    }
                    Text(viewModel.snapshot.phase.displayLabel)
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.snapshot.phaseLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                if let countdown = viewModel.snapshot.periodCountdownLabel {
                    Text(countdown)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textSecondary)
                }
                Text("Cycle ~\(viewModel.snapshot.averageCycleLengthDays) days · Period ~\(viewModel.snapshot.averagePeriodLengthDays) days")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    private var phaseProgress: CGFloat {
        guard let day = viewModel.snapshot.cycleDay else { return 0.3 }
        let length = max(viewModel.snapshot.averageCycleLengthDays, 1)
        return min(CGFloat(day) / CGFloat(length), 1)
    }

    @ViewBuilder
    private var insightSection: some View {
        if let insight = viewModel.insights.first {
            VStack(alignment: .leading, spacing: 8) {
                Label("Today's insight", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                Text(insight.headline)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                Text(insight.body)
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        }
    }

    private var calendarStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 60 days")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(stripDays, id: \.self) { day in
                        let start = Calendar.current.startOfDay(for: day)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color(for: start))
                            .frame(width: 8, height: 24)
                    }
                }
            }
            HStack(spacing: 16) {
                legendDot(color: DesignSystem.accentPrimary.opacity(0.8), label: "Period")
                legendDot(color: DesignSystem.accentPrimary.opacity(0.25), label: "Predicted")
            }
            .font(.system(size: 10))
            .foregroundColor(DesignSystem.textMuted)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    private var stripDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<60).compactMap { calendar.date(byAdding: .day, value: -59 + $0, to: today) }
    }

    private func color(for day: Date) -> Color {
        if viewModel.periodHighlightDays.contains(day) {
            return DesignSystem.accentPrimary.opacity(0.85)
        }
        if viewModel.predictedPeriodDays.contains(day) {
            return DesignSystem.accentPrimary.opacity(0.25)
        }
        return Color.white.opacity(0.08)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    @ViewBuilder
    private var symptomHistorySection: some View {
        let items = viewModel.symptomFrequency(for: viewModel.snapshot.phase)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Common in \(viewModel.snapshot.phase.displayLabel.lowercased()) phase")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                ForEach(items.prefix(5), id: \.0) { symptom, count in
                    HStack {
                        Text(symptom)
                            .font(.system(size: 13))
                        Spacer()
                        Text("\(count)×")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        }
    }

    private var quickLogButton: some View {
        Button {
            showQuickLog = true
        } label: {
            Label("Log how you feel", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
    }

    private var disclaimer: some View {
        Text(UserFacingCopy.medicalDisclaimerWithProvider)
            .font(.system(size: 11))
            .foregroundColor(DesignSystem.textMuted)
    }
}

#Preview {
    NavigationStack {
        CycleDashboardView()
    }
}
