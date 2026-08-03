import Foundation
import LookAfterCore

/// Builds compact AI context from precomputed analytics (no raw HealthKit replay).
public enum AIContextBuilder {

    public static func build(
        snapshots: [AnalyticsDailySnapshot],
        weeklyReport: PersonalAnalyticsReport?,
        calendar: Calendar = .current
    ) -> CachedAIContextSummary {
        let today = calendar.startOfDay(for: Date())
        let todayKey = AnalyticsDailySnapshot.dayKey(for: today, calendar: calendar)
        let todaySnapshot = snapshots.first { $0.id == todayKey }

        let last7 = snapshots.filter {
            guard let date = $0.date as Date? else { return false }
            return date >= (calendar.date(byAdding: .day, value: -6, to: today) ?? today)
        }

        let sleepValues = last7.compactMap(\.sleepHours)
        let sleepAverage = average(sleepValues)
        let sleepTrend = trendLabel(values: sleepValues)

        let weeklyTasks = last7.reduce(0) { $0 + $1.tasksCompleted }
        let weeklyCompletion: Int? = weeklyTasks > 0
            ? min(100, weeklyTasks * 10)
            : weeklyReport?.kpis.completedTasksCount.map { min(100, $0 * 10) }

        let focusMinutes = last7.reduce(0) { $0 + $1.focusMinutes }
        let deepWorkHours = focusMinutes > 0 ? Double(focusMinutes) / 60.0 : nil

        return CachedAIContextSummary(
            sleepAverage: sleepAverage,
            sleepTrend: sleepTrend,
            energyScore: todaySnapshot?.efScore ?? weeklyReport?.kpis.averageExecutiveFunctionScore,
            stepsToday: todaySnapshot?.steps,
            weeklyTaskCompletion: weeklyCompletion,
            deepWorkHours: deepWorkHours,
            workoutStreak: nil,
            habitAdherencePercent: weeklyReport?.kpis.habitAdherencePercent,
            peakProductivityWindow: weeklyReport?.kpis.peakProductivityWindow,
            generatedAt: Date(),
            isStale: false
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func trendLabel(values: [Double]) -> String? {
        guard values.count >= 4 else { return nil }
        let midpoint = values.count / 2
        let first = values.prefix(midpoint)
        let second = values.suffix(values.count - midpoint)
        let firstAvg = first.reduce(0, +) / Double(first.count)
        let secondAvg = second.reduce(0, +) / Double(second.count)
        if secondAvg > firstAvg + 0.2 { return "improving" }
        if secondAvg < firstAvg - 0.2 { return "declining" }
        return "stable"
    }
}
