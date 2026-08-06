import SwiftUI
import LookAfterCore

// MARK: - Weekly Review View

/// Weekly Debrief surface — pure summary in, calm narrative out.
struct WeeklyReviewView: View {
    let summary: WeeklyReviewSummary

    private let columns = [
        GridItem(.flexible(), spacing: DesignSystem.spacingSM),
        GridItem(.flexible(), spacing: DesignSystem.spacingSM)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                header
                if hasWeeklyActivity {
                    heroCard
                    metricsGrid
                    executiveSummaryCard
                } else {
                    emptyStateCard
                }
            }
            .padding(.horizontal, DesignSystem.spacingMD)
            .padding(.top, DesignSystem.spacingMD)
            .padding(.bottom, 48)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityIdentifier("screen-weekly-review")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekly Debrief")
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)
            Text(dateBoundsLabel)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hero (Time-Bank Balance)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME RECLAIMED")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                        .tracking(0.6)
                    Text(hoursLabel(summary.timeReclaimedHours))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                equilibriumBadge
            }

            Text("Automated cascade actions protected this time so it stayed yours.")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
                .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Time reclaimed \(hoursLabel(summary.timeReclaimedHours)), equilibrium \(summary.equilibriumPercent) percent"
        )
    }

    private var equilibriumBadge: some View {
        Text("\(summary.equilibriumPercent)%")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(DesignSystem.accentOnPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignSystem.accentPrimary)
            )
            .accessibilityLabel("Equilibrium score \(summary.equilibriumPercent) percent")
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        LazyVGrid(columns: columns, spacing: DesignSystem.spacingSM) {
            MetricTile(
                title: "Deep Focus",
                value: hoursLabel(summary.totalFocusHoursCompleted),
                icon: "brain.head.profile",
                tint: DesignSystem.focus
            )
            MetricTile(
                title: "Sabotage Actions",
                value: "\(summary.sabotageAuctionsTriggered)",
                icon: "shield.checkered",
                tint: DesignSystem.warning
            )
            MetricTile(
                title: "Deduplicated",
                value: "\(summary.tasksSupersededCount)",
                icon: "arrow.triangle.merge",
                tint: DesignSystem.reflection
            )
            MetricTile(
                title: "Cleanly Expired",
                value: "\(summary.tasksExpiredCount)",
                icon: "clock.badge.xmark",
                tint: DesignSystem.textMuted
            )
            MetricTile(
                title: "Flexible Shifts",
                value: "\(summary.flexibleShiftsExecuted)",
                icon: "arrow.right.circle",
                tint: DesignSystem.accentPrimary
            )
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text("Your first debrief is building")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
            Text("Complete tasks and let the schedule engine run for a few days. Cascade actions and focus hours will appear here automatically.")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
    }

    private var hasWeeklyActivity: Bool {
        summary.totalFocusHoursCompleted > 0
            || summary.timeReclaimedHours > 0
            || summary.sabotageAuctionsTriggered > 0
            || summary.tasksSupersededCount > 0
            || summary.tasksExpiredCount > 0
            || summary.flexibleShiftsExecuted > 0
    }

    // MARK: - Executive Summary

    private var executiveSummaryCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text("Executive Summary")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
            Text(Self.executiveNarrative(for: summary))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private var dateBoundsLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        let start = f.string(from: summary.weekStartDate)
        let end = f.string(from: summary.weekEndDate)
        return "\(start) – \(end)"
    }

    private func hoursLabel(_ hours: Double) -> String {
        if hours == 0 { return "0h" }
        if hours < 10 {
            return String(format: "%.1fh", hours)
        }
        return String(format: "%.0fh", hours.rounded())
    }

    /// Dynamic Chief of Staff copy from weekly metrics.
    static func executiveNarrative(for summary: WeeklyReviewSummary) -> String {
        if summary.highLoadStreakDays >= 4 {
            let blocks = max(summary.sabotageAuctionsTriggered, 0)
            let blockPhrase = blocks == 1
                ? "1 recovery block"
                : "\(blocks) recovery blocks"
            return "This was a dense week — \(summary.highLoadStreakDays) consecutive high-load days. The engine forced \(blockPhrase) so capacity could reset without you negotiating every gap."
        }

        let focus = String(format: "%.1f", summary.totalFocusHoursCompleted)
        let ephemeral = summary.tasksExpiredCount + summary.tasksSupersededCount
        if ephemeral == 0 {
            return "You completed \(focus) hours of deep focus. The schedule stayed clean — no ephemeral items needed to be retired."
        }
        let noun = ephemeral == 1 ? "item" : "items"
        return "You completed \(focus) hours of deep focus. The engine cleanly handled \(ephemeral) ephemeral \(noun) so the day never double-stacked or clung to missed windows."
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = DesignSystem.accentPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.textSecondary)
                .lineLimit(2)
        }
        .padding(DesignSystem.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    WeeklyReviewView(
        summary: WeeklyReviewSummary(
            weekStartDate: Calendar.current.date(byAdding: .day, value: -6, to: Date())!,
            weekEndDate: Date(),
            totalFocusHoursCompleted: 12.5,
            timeReclaimedHours: 3.5,
            highLoadStreakDays: 5,
            sabotageAuctionsTriggered: 2,
            tasksSupersededCount: 3,
            tasksExpiredCount: 1,
            flexibleShiftsExecuted: 4,
            equilibriumScore: 0.76
        )
    )
}
#endif
