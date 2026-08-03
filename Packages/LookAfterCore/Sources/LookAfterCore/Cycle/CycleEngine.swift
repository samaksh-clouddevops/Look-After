import Foundation

public enum CycleEngine {

    public struct Input: Sendable {
        public var preferences: CycleTrackingPreferences
        public var logs: [CycleDayLog]
        public var now: Date
        public var calendar: Calendar

        public init(
            preferences: CycleTrackingPreferences = CyclePreferencesStore.load(),
            logs: [CycleDayLog] = CycleLogStore.load(),
            now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.preferences = preferences
            self.logs = logs
            self.now = now
            self.calendar = calendar
        }
    }

    public static func snapshot(_ input: Input) -> CycleSnapshot {
        guard input.preferences.isEnabled else { return .disabled }

        let cycleLength = learnedCycleLength(input: input) ?? input.preferences.averageCycleLengthDays
        let periodLength = learnedPeriodLength(input: input) ?? input.preferences.averagePeriodLengthDays

        guard let anchor = currentCycleAnchor(input: input, cycleLength: cycleLength) else {
            return CycleSnapshot(
                cycleDay: nil,
                phase: .unknown,
                daysUntilPeriod: nil,
                predictedPeriodStart: nil,
                confidence: .low,
                averageCycleLengthDays: cycleLength,
                averagePeriodLengthDays: periodLength,
                isEnabled: true
            )
        }

        let today = input.calendar.startOfDay(for: input.now)
        let anchorDay = input.calendar.startOfDay(for: anchor)
        let daysSinceStart = max(input.calendar.dateComponents([.day], from: anchorDay, to: today).day ?? 0, 0)
        let cycleDay = min(daysSinceStart + 1, max(cycleLength, 1))
        let phase = phase(for: cycleDay, cycleLength: cycleLength, periodLength: periodLength)
        let daysUntilPeriod = max(cycleLength - cycleDay, 0)
        let predictedStart = input.calendar.date(byAdding: .day, value: daysUntilPeriod, to: today)
        let confidence = confidenceLevel(input: input, cycleLength: cycleLength)

        return CycleSnapshot(
            cycleDay: cycleDay,
            phase: phase,
            daysUntilPeriod: daysUntilPeriod,
            predictedPeriodStart: predictedStart,
            confidence: confidence,
            averageCycleLengthDays: cycleLength,
            averagePeriodLengthDays: periodLength,
            isEnabled: true
        )
    }

    public static func periodDays(in range: ClosedRange<Date>, input: Input) -> Set<Date> {
        guard input.preferences.isEnabled else { return [] }
        let cycleLength = learnedCycleLength(input: input) ?? input.preferences.averageCycleLengthDays
        let periodLength = learnedPeriodLength(input: input) ?? input.preferences.averagePeriodLengthDays
        guard let firstAnchor = rawLastPeriodStart(input: input) else { return [] }

        var result = Set<Date>()
        var cursor = input.calendar.startOfDay(for: firstAnchor)
        let rangeStart = input.calendar.startOfDay(for: range.lowerBound)
        let rangeEnd = input.calendar.startOfDay(for: range.upperBound)

        // Walk back to cover the range if the first anchor is after rangeStart.
        while let previous = input.calendar.date(byAdding: .day, value: -cycleLength, to: cursor),
              previous >= rangeStart {
            cursor = previous
        }

        while cursor <= rangeEnd {
            for offset in 0..<periodLength {
                guard let day = input.calendar.date(byAdding: .day, value: offset, to: cursor) else { break }
                if day >= rangeStart && day <= rangeEnd {
                    result.insert(day)
                }
            }
            guard let next = input.calendar.date(byAdding: .day, value: cycleLength, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    public static func symptomFrequencyByPhase(input: Input) -> [CyclePhase: [String: Int]] {
        guard input.preferences.isEnabled else { return [:] }
        var counts: [CyclePhase: [String: Int]] = [:]
        for log in input.logs {
            let snap = snapshot(Input(preferences: input.preferences, logs: input.logs, now: log.day, calendar: input.calendar))
            guard snap.cycleDay != nil, snap.phase != .unknown else { continue }
            let phase = snap.phase
            for symptom in log.symptoms {
                var phaseCounts = counts[phase, default: [:]]
                phaseCounts[symptom, default: 0] += 1
                counts[phase] = phaseCounts
            }
        }
        return counts
    }

    /// Whether logging flow on this day should update the stored period start.
    public static func shouldTreatFlowAsNewPeriodStart(
        log: CycleDayLog,
        logs: [CycleDayLog],
        preferences: CycleTrackingPreferences,
        calendar: Calendar = .current
    ) -> Bool {
        guard let flow = log.flow, flow != .none, flow != .spotting else { return false }
        let day = calendar.startOfDay(for: log.day)
        let minGap = max(min(preferences.averageCycleLengthDays - 7, 21), 14)

        if let lastStart = preferences.lastPeriodStart {
            let start = calendar.startOfDay(for: lastStart)
            let gap = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            if gap >= minGap { return true }
            if gap >= 0 && gap < minGap { return false }
        }

        let priorFlow = logs
            .filter { log in
                guard let flow = log.flow, flow != .none, flow != .spotting else { return false }
                let logDay = calendar.startOfDay(for: log.day)
                return logDay < day
            }
            .map { calendar.startOfDay(for: $0.day) }
            .max()

        guard let priorFlow else { return true }
        let gap = calendar.dateComponents([.day], from: priorFlow, to: day).day ?? 0
        return gap >= minGap
    }

    // MARK: - Private

    private static func currentCycleAnchor(input: Input, cycleLength: Int) -> Date? {
        guard let raw = rawLastPeriodStart(input: input) else { return nil }
        return rolledCycleAnchor(
            from: raw,
            today: input.now,
            cycleLength: cycleLength,
            calendar: input.calendar
        )
    }

    private static func rawLastPeriodStart(input: Input) -> Date? {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        let logStarts = periodStarts(from: input.logs, calendar: calendar)

        if let manual = input.preferences.lastPeriodStart {
            let manualStart = calendar.startOfDay(for: manual)
            if let logStart = logStarts.last, logStart > manualStart {
                let gap = calendar.dateComponents([.day], from: manualStart, to: logStart).day ?? 0
                let minGap = max(min(input.preferences.averageCycleLengthDays - 7, 21), 14)
                if gap >= minGap, logStart <= today {
                    return logStart
                }
            }
            return manualStart
        }

        return logStarts.filter { $0 <= today }.max()
    }

    private static func rolledCycleAnchor(
        from lastStart: Date,
        today: Date,
        cycleLength: Int,
        calendar: Calendar
    ) -> Date {
        let todayStart = calendar.startOfDay(for: today)
        var anchor = calendar.startOfDay(for: lastStart)
        guard cycleLength > 0 else { return anchor }

        while let nextStart = calendar.date(byAdding: .day, value: cycleLength, to: anchor),
              nextStart <= todayStart {
            anchor = nextStart
        }
        return anchor
    }

    private static func learnedCycleLength(input: Input) -> Int? {
        let starts = periodStarts(from: input.logs, calendar: input.calendar)
        guard starts.count >= 2 else { return nil }
        var lengths: [Int] = []
        for index in 1..<starts.count {
            let days = input.calendar.dateComponents([.day], from: starts[index - 1], to: starts[index]).day ?? 0
            if (21...45).contains(days) { lengths.append(days) }
        }
        guard !lengths.isEmpty else { return nil }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    private static func learnedPeriodLength(input: Input) -> Int? {
        let starts = periodStarts(from: input.logs, calendar: input.calendar)
        guard !starts.isEmpty else { return nil }
        var lengths: [Int] = []
        for start in starts {
            let consecutive = input.logs
                .filter { log in
                    guard let flow = log.flow, flow != .none else { return false }
                    let delta = input.calendar.dateComponents([.day], from: start, to: log.day).day ?? 99
                    return delta >= 0 && delta < 10
                }
                .map { input.calendar.dateComponents([.day], from: start, to: $0.day).day ?? 0 }
            if let maxDay = consecutive.max() {
                lengths.append(maxDay + 1)
            }
        }
        guard !lengths.isEmpty else { return nil }
        return min(max(Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded()), 2), 10)
    }

    private static func periodStarts(from logs: [CycleDayLog], calendar: Calendar) -> [Date] {
        let sorted = logs
            .filter { $0.flow == .medium || $0.flow == .heavy || $0.flow == .light }
            .sorted { $0.day < $1.day }
        var starts: [Date] = []
        for log in sorted {
            let day = calendar.startOfDay(for: log.day)
            if let last = starts.last {
                let gap = calendar.dateComponents([.day], from: last, to: day).day ?? 0
                if gap >= 10 { starts.append(day) }
            } else {
                starts.append(day)
            }
        }
        return starts
    }

    private static func phase(for cycleDay: Int, cycleLength: Int, periodLength: Int) -> CyclePhase {
        if cycleDay <= periodLength { return .menstrual }
        let mid = max(cycleLength / 2, periodLength + 1)
        if cycleDay <= mid - 2 { return .follicular }
        if cycleDay <= mid + 2 { return .ovulation }
        return .luteal
    }

    private static func confidenceLevel(input: Input, cycleLength: Int) -> CycleConfidence {
        let starts = periodStarts(from: input.logs, calendar: input.calendar)
        if starts.count >= 3 { return .high }
        if starts.count >= 2 || input.preferences.lastPeriodStart != nil { return .medium }
        if !input.logs.isEmpty { return .low }
        return .low
    }
}
