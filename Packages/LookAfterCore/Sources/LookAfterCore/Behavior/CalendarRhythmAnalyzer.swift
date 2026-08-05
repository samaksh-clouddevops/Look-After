import Foundation

// MARK: - Input (EventKit-free)

/// Lightweight calendar event for on-device clustering. Map from `EKEvent` at the app boundary.
public struct CalendarHistoryEvent: Sendable, Equatable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var title: String

    public init(
        id: String = UUID().uuidString,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        title: String = ""
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.title = title
    }

    public var durationMinutes: Double {
        max(0, end.timeIntervalSince(start) / 60.0)
    }
}

// MARK: - Mathematical rhythm profile (never expose labels to LLM/UI)

/// Pure numeric weekly cadence derived from calendar density — no persona names.
public struct RhythmProfile: Codable, Sendable, Equatable {
    /// Weekday 1…7 (Calendar weekday) → density 0…1 (meeting load).
    public var weekdayDensity: [Int: Double]
    /// Typical workday start hour (0…23), continuous.
    public var typicalStartHour: Double
    /// Typical workday end hour (0…23), continuous.
    public var typicalEndHour: Double
    /// Fraction of weekdays classified high-density.
    public var highDensityWeekdayFraction: Double
    /// Mean events per active day.
    public var meanEventsPerDay: Double
    /// Preferred deep-work TimeConstraint per TOD bucket (mathematical mapping only).
    public var todBaselineConstraint: [BehavioralTimeOfDay: TimeConstraint]
    /// Preferred meeting constraint (usually anchored when density high).
    public var meetingBaselineConstraint: TimeConstraint
    public var analyzedEventCount: Int
    public var generatedAt: Date

    public init(
        weekdayDensity: [Int: Double] = [:],
        typicalStartHour: Double = 9,
        typicalEndHour: Double = 17,
        highDensityWeekdayFraction: Double = 0,
        meanEventsPerDay: Double = 0,
        todBaselineConstraint: [BehavioralTimeOfDay: TimeConstraint] = [:],
        meetingBaselineConstraint: TimeConstraint = .flexible,
        analyzedEventCount: Int = 0,
        generatedAt: Date = Date()
    ) {
        self.weekdayDensity = weekdayDensity
        self.typicalStartHour = typicalStartHour
        self.typicalEndHour = typicalEndHour
        self.highDensityWeekdayFraction = highDensityWeekdayFraction
        self.meanEventsPerDay = meanEventsPerDay
        self.todBaselineConstraint = todBaselineConstraint
        self.meetingBaselineConstraint = meetingBaselineConstraint
        self.analyzedEventCount = analyzedEventCount
        self.generatedAt = generatedAt
    }

    public func density(weekday: Int) -> Double {
        weekdayDensity[weekday] ?? 0
    }

    public func isHighDensity(weekday: Int, threshold: Double = 0.55) -> Bool {
        density(weekday: weekday) >= threshold
    }
}

// MARK: - Analyzer

/// On-device calendar-graph heuristics + 1D k-means on daily load.
public enum CalendarRhythmAnalyzer {
    public static let historyDays = 183 // ~6 months

    public static func analyze(
        events: [CalendarHistoryEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RhythmProfile {
        let timed = events.filter { !$0.isAllDay && $0.durationMinutes > 0 && $0.durationMinutes < 12 * 60 }
        guard !timed.isEmpty else {
            return RhythmProfile(generatedAt: now)
        }

        // Group by day → composite load [eventCount + hours]
        let dayGroups = Dictionary(grouping: timed) { calendar.startOfDay(for: $0.start) }
        var dayRecords: [(day: Date, load: Double, events: [CalendarHistoryEvent])] = []

        for (day, dayEvents) in dayGroups {
            let count = Double(dayEvents.count)
            let minutes = dayEvents.reduce(0.0) { $0 + $1.durationMinutes }
            let load = count + minutes / 60.0
            dayRecords.append((day, load, dayEvents))
        }

        let rawLoads = dayRecords.map(\.load)
        // Strip vacation / crunch outliers before k-means so centroids reflect typical life.
        let inlierMask = iqrInlierMask(values: rawLoads, lowerFence: 0.05, upperFence: 0.95)
        let inlierRecords = dayRecords.enumerated().compactMap { idx, rec in
            inlierMask[idx] ? rec : nil
        }
        // Fall back to all days if filtering would erase the sample.
        let working = inlierRecords.count >= max(4, dayRecords.count / 5) ? inlierRecords : dayRecords
        let dayLoads = working.map(\.load)

        var startHours: [Double] = []
        var endHours: [Double] = []
        var weekdayAccum: [Int: (sum: Double, n: Int)] = [:]
        var inlierEventCount = 0

        for rec in working {
            inlierEventCount += rec.events.count
            let sorted = rec.events.sorted { $0.start < $1.start }
            if let first = sorted.first {
                startHours.append(hourFraction(first.start, calendar: calendar))
            }
            if let last = sorted.last {
                endHours.append(hourFraction(last.end, calendar: calendar))
            }
            let wd = calendar.component(.weekday, from: rec.day)
            let prev = weekdayAccum[wd] ?? (0, 0)
            weekdayAccum[wd] = (prev.sum + rec.load, prev.n + 1)
        }

        let centroids = kMeans1D(values: dayLoads, k: 2, iterations: 12)
        let highCentroid = centroids.max() ?? 1
        let lowCentroid = centroids.min() ?? 0
        let split = (highCentroid + lowCentroid) / 2

        var weekdayDensity: [Int: Double] = [:]
        for (wd, acc) in weekdayAccum {
            let mean = acc.n > 0 ? acc.sum / Double(acc.n) : 0
            weekdayDensity[wd] = highCentroid > 0 ? min(1, mean / highCentroid) : 0
        }

        let highDays = dayLoads.filter { $0 >= split }.count
        let highFrac = dayLoads.isEmpty ? 0 : Double(highDays) / Double(dayLoads.count)
        let meanEvents = working.isEmpty ? 0 : Double(inlierEventCount) / Double(working.count)

        let startHour = percentile(startHours, p: 0.25) ?? 9
        let endHour = percentile(endHours, p: 0.75) ?? 17

        // Map density → baseline constraints (math only; no persona strings).
        let meetingConstraint: TimeConstraint = highFrac >= 0.4 ? .anchored : .flexible
        var tod: [BehavioralTimeOfDay: TimeConstraint] = [:]
        tod[.morning] = startHour <= 9.5 && highFrac < 0.65 ? .flexible : .fluid
        tod[.afternoon] = highFrac >= 0.5 ? .anchored : .flexible
        tod[.evening] = endHour >= 18.5 ? .flexible : .fluid

        return RhythmProfile(
            weekdayDensity: weekdayDensity,
            typicalStartHour: startHour,
            typicalEndHour: endHour,
            highDensityWeekdayFraction: highFrac,
            meanEventsPerDay: meanEvents,
            todBaselineConstraint: tod,
            meetingBaselineConstraint: meetingConstraint,
            analyzedEventCount: timed.count,
            generatedAt: now
        )
    }

    // MARK: - Clustering helpers

    /// Percentile-fence filter (default drop bottom/top 5%) to exclude vacations & crunch weeks.
    /// Returns a parallel mask; `true` = keep for clustering.
    public static func iqrInlierMask(
        values: [Double],
        lowerFence: Double = 0.05,
        upperFence: Double = 0.95
    ) -> [Bool] {
        guard values.count >= 8 else {
            return Array(repeating: true, count: values.count)
        }
        let lo = percentile(values, p: lowerFence) ?? values.min() ?? 0
        let hi = percentile(values, p: upperFence) ?? values.max() ?? 0
        // Also apply classic IQR fences when spread is wide.
        let q1 = percentile(values, p: 0.25) ?? lo
        let q3 = percentile(values, p: 0.75) ?? hi
        let iqr = max(q3 - q1, 0)
        let iqrLo = q1 - 1.5 * iqr
        let iqrHi = q3 + 1.5 * iqr
        let lowBound = max(lo, iqrLo)
        let highBound = min(hi, iqrHi)
        return values.map { $0 >= lowBound && $0 <= highBound }
    }

    public static func filterOutliers(_ values: [Double]) -> [Double] {
        let mask = iqrInlierMask(values: values)
        return values.enumerated().compactMap { mask[$0.offset] ? $0.element : nil }
    }

    /// Simple 1D k-means for daily load separation (high vs sparse).
    public static func kMeans1D(values: [Double], k: Int, iterations: Int) -> [Double] {
        guard !values.isEmpty else { return Array(repeating: 0, count: max(k, 1)) }
        let kk = min(max(k, 1), values.count)
        let sorted = values.sorted()
        var centroids: [Double] = (0..<kk).map { i in
            let idx = min(sorted.count - 1, (sorted.count - 1) * i / max(kk - 1, 1))
            return sorted[idx]
        }

        for _ in 0..<iterations {
            var buckets = Array(repeating: [Double](), count: centroids.count)
            for v in values {
                let nearest = centroids.enumerated().min(by: {
                    abs($0.element - v) < abs($1.element - v)
                })?.offset ?? 0
                buckets[nearest].append(v)
            }
            for i in centroids.indices where !buckets[i].isEmpty {
                centroids[i] = buckets[i].reduce(0, +) / Double(buckets[i].count)
            }
        }
        return centroids
    }

    public static func hourFraction(_ date: Date, calendar: Calendar) -> Double {
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        return Double(h) + Double(m) / 60.0
    }

    public static func percentile(_ values: [Double], p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(1, max(0, p))
        let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * clamped).rounded())))
        return sorted[idx]
    }
}
