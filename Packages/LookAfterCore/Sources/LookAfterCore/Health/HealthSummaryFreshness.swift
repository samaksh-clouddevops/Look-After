import Foundation

/// Determines whether health summaries represent last night's sleep vs stale carry-over.
public enum HealthSummaryFreshness {

    /// True when the summary includes sleep attributable to waking up today (or dated today with sleep).
    public static func hasLastNightSleep(
        _ summary: HealthSummary,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard (summary.totalSleepMinutes ?? 0) > 0 else { return false }

        let todayStart = calendar.startOfDay(for: now)

        if calendar.isDate(summary.date, inSameDayAs: now) {
            return true
        }

        if let wake = summary.wakeTime, wake >= todayStart {
            return true
        }

        if let bedtime = summary.bedtime,
           wakeTimeImpliedToday(bedtime: bedtime, wake: summary.wakeTime, now: now, calendar: calendar) {
            return true
        }

        // Apple Health often dates overnight sleep to the calendar day of bedtime.
        // Treat recent sleep (within 36h) as last night when wake was today-ish or missing.
        let age = now.timeIntervalSince(summary.date)
        if age >= 0, age <= 36 * 60 * 60 {
            if let wake = summary.wakeTime {
                return wake >= todayStart.addingTimeInterval(-6 * 60 * 60)
            }
            return true
        }

        return false
    }

    /// Strips stale overnight metrics so briefing/cognitive models do not treat yesterday as last night.
    public static func forBriefingMetrics(
        from summary: HealthSummary?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HealthSummary? {
        guard var summary else { return nil }

        if hasLastNightSleep(summary, now: now, calendar: calendar) {
            return summary
        }

        summary.totalSleepMinutes = nil
        summary.deepSleepMinutes = nil
        summary.remSleepMinutes = nil
        summary.coreSleepMinutes = nil
        summary.awakeMinutes = nil
        summary.sleepQualityScore = nil
        summary.bedtime = nil
        summary.wakeTime = nil

        // Overnight recovery signals (HRV/RHR) belong with last night's sleep — drop when sleep is missing/stale.
        if !calendar.isDate(summary.date, inSameDayAs: now) {
            summary.hrvAverage = nil
            summary.restingHeartRate = nil
            summary.averageHeartRate = nil
        }

        return summary
    }

    private static func wakeTimeImpliedToday(
        bedtime: Date,
        wake: Date?,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let todayStart = calendar.startOfDay(for: now)
        if let wake, wake >= todayStart { return true }
        // Bedtime yesterday evening with no wake yet — still not valid "last night" after morning.
        return false
    }
}
