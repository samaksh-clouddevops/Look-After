import SwiftUI
import LifeOSCore
import LifeOSFeatures

/// Compact horizontal metrics strip — timeline stays hero; details expand on demand.
struct TodayCompactMetricsStrip: View {
    let metrics: [TodayExecutiveMetric]
    let capacity: ExecutiveCapacityState

    var onMetricTap: (TodayMetricKind) -> Void

    @State private var isExpanded = false
    @GestureState private var dragOffset: CGFloat = 0

    private let collapsedHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stripRow

            if isExpanded {
                expandedCapacityPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isExpanded)
    }

    // MARK: - Collapsed strip

    private var stripRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(metrics) { metric in
                        metricCapsule(metric)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded() }

            expandChevron
        }
        .frame(height: collapsedHeight)
    }

    private func metricCapsule(_ metric: TodayExecutiveMetric) -> some View {
        Button {
            onMetricTap(metric.kind)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: metric.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(metric.value)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(metric.isHighlighted ? DesignSystem.accentPrimary : DesignSystem.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignSystem.backgroundElevated.opacity(0.85))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                metric.isHighlighted
                                    ? DesignSystem.accentPrimary.opacity(0.35)
                                    : DesignSystem.divider.opacity(0.6),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var expandChevron: some View {
        Button(action: toggleExpanded) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(DesignSystem.backgroundElevated.opacity(0.85))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse capacity details" : "Expand capacity details")
    }

    // MARK: - Expanded capacity panel

    private var expandedCapacityPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            HStack(alignment: .firstTextBaseline) {
                Text("Executive Capacity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Text(capacity.band.displayLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
            }

            if !capacity.reasoning.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                    ForEach(capacity.reasoning.reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(DesignSystem.textMuted)
                            Text(reason)
                                .font(.system(size: 13))
                                .foregroundColor(DesignSystem.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !capacity.forecast.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Predicted Capacity")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)

                    ForEach(Array(capacity.forecast.enumerated()), id: \.element.id) { index, point in
                        HStack(spacing: 8) {
                            if index > 0 {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(DesignSystem.textMuted.opacity(0.6))
                            }
                            Text(point.timeLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DesignSystem.textSecondary)
                            Text(point.band.shortLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DesignSystem.textPrimary)
                        }
                    }
                }
            }
        }
        .padding(DesignSystem.spacingMD)
        .padding(.top, DesignSystem.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.backgroundElevated.opacity(0.5))
        )
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 24 { isExpanded = false }
                }
        )
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }
}

// MARK: - Detail sheets

struct TodayMetricDetailSheet: View {
    let kind: TodayMetricKind
    let briefingVM: DailyBriefingViewModel
    let capacity: ExecutiveCapacityState
    let weatherSnapshot: WeatherDisplayService.Snapshot

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                    switch kind {
                    case .capacity:
                        capacityDetail
                    case .sleep:
                        sleepDetail
                    case .recovery:
                        recoveryDetail
                    case .medication:
                        medicationDetail
                    case .cycle:
                        cycleDetail
                    case .freeTime:
                        calendarDetail
                    case .weather:
                        weatherDetail
                    case .focusWindow:
                        focusDetail
                    case .momentum:
                        momentumDetail
                    }
                }
                .padding(DesignSystem.spacingLG)
            }
            .background(DesignSystem.backgroundPrimary.ignoresSafeArea())
            .navigationTitle(detailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var detailTitle: String {
        switch kind {
        case .capacity: return "Executive Capacity"
        case .sleep: return "Sleep"
        case .recovery: return "Recovery"
        case .medication: return "Medication"
        case .cycle: return "Cycle"
        case .freeTime: return "Schedule"
        case .weather: return "Weather"
        case .focusWindow: return "Focus Window"
        case .momentum: return "Momentum"
        }
    }

    private var capacityDetail: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            Text(capacity.band.displayLabel)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)
            Text(capacity.band.tagline)
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.textSecondary)
            detailSection("Why", items: capacity.reasoning.reasons)
            detailSection("Best for", items: capacity.reasoning.recommendedWorkTypes)
            if !capacity.reasoning.avoidWorkTypes.isEmpty {
                detailSection("Avoid", items: capacity.reasoning.avoidWorkTypes)
            }
        }
    }

    private var sleepDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hours = briefingVM.sleep.totalHours {
                Text(formatSleep(hours))
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(DesignSystem.textPrimary)
            }
            if let quality = briefingVM.healthSnapshot.sleepQuality {
                detailRow("Quality", value: quality)
            }
            if briefingVM.sleep.sleepDebtHours >= 1 {
                detailRow("Sleep debt", value: String(format: "%.1fh", briefingVM.sleep.sleepDebtHours))
            }
            if let ideal = briefingVM.dayBriefing?.idealSleepLine {
                detailRow("Ideal tonight", value: ideal.replacingOccurrences(of: "Ideal tonight: ", with: ""))
            }
        }
    }

    private var recoveryDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(briefingVM.healthSnapshot.recoveryLabel)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
            detailRow("Readiness", value: briefingVM.healthSnapshot.readinessBand)
            if briefingVM.health.isAvailable, let hrv = briefingVM.health.hrv {
                detailRow("HRV", value: "\(hrv) ms")
            }
        }
    }

    private var cycleDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if briefingVM.cycleData.isVisible {
                Text(briefingVM.cycleData.snapshot.phaseLabel)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                if let countdown = briefingVM.cycleData.snapshot.periodCountdownLabel {
                    detailRow("Next period", value: countdown)
                }
                if let insight = briefingVM.cycleData.topInsight {
                    detailRow("Insight", value: insight.headline)
                    Text(insight.body)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textSecondary)
                }
            } else {
                Text("Enable cycle tracking in Settings for phase-aware insights.")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.textSecondary)
            }
            Text("LifeOS is not a medical device.")
                .font(.system(size: 11))
                .foregroundColor(DesignSystem.textMuted)
        }
    }

    private var medicationDetail: some View {
        Text("Open Medication in Modules for your full schedule.")
            .font(.system(size: 14))
            .foregroundColor(DesignSystem.textSecondary)
    }

    private var calendarDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = briefingVM.calendar.nextEventTitle {
                detailRow("Next", value: title)
                if let mins = briefingVM.calendar.minutesUntilStart {
                    detailRow("Starts in", value: "\(mins) min")
                }
            } else {
                Text("No upcoming meetings.")
                    .foregroundColor(DesignSystem.textSecondary)
            }
        }
    }

    private var weatherDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if weatherSnapshot.isAvailable {
                if let temp = weatherSnapshot.temperatureCelsius {
                    Text("\(temp)°C")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(DesignSystem.textPrimary)
                }
                Text(weatherSnapshot.conditionLabel)
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.textSecondary)
            } else {
                Text("Weather unavailable.")
                    .foregroundColor(DesignSystem.textSecondary)
            }
        }
    }

    private var focusDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(briefingVM.healthSnapshot.focusWindow)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignSystem.textPrimary)
            ForEach(briefingVM.focusWindows) { window in
                detailRow(window.label, value: window.timeRange)
            }
        }
    }

    private var momentumDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("Completed today", value: "\(briefingVM.progress.completedCount)")
            detailRow("Remaining", value: "\(briefingVM.progress.remainingCount)")
        }
    }

    @ViewBuilder
    private func detailSection(_ title: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.textSecondary)
                }
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
        }
    }

    private func formatSleep(_ hours: Double) -> String {
        let whole = Int(hours)
        let minutes = Int((hours - Double(whole)) * 60)
        if minutes > 0 { return "\(whole)h \(minutes)m" }
        return "\(whole)h"
    }
}
