import Foundation

// MARK: - Input / output

/// HealthKit-agnostic sleep sample for aggregation and unit tests.
public struct SleepSampleInput: Sendable, Equatable {
    public var start: Date
    public var end: Date
    /// Raw `HKCategoryValueSleepAnalysis` value.
    public var categoryValue: Int
    public var sourceBundleId: String
    public var sourceName: String

    public init(
        start: Date,
        end: Date,
        categoryValue: Int,
        sourceBundleId: String,
        sourceName: String = ""
    ) {
        self.start = start
        self.end = end
        self.categoryValue = categoryValue
        self.sourceBundleId = sourceBundleId
        self.sourceName = sourceName
    }

    var durationMinutes: Double {
        max(0, end.timeIntervalSince(start) / 60.0)
    }
}

/// Aggregated "last night" sleep — deduplicated across sources and sessions.
public struct SleepNightResult: Sendable, Equatable {
    public var totalAsleepMinutes: Double
    public var deepMinutes: Double
    public var remMinutes: Double
    public var coreMinutes: Double
    public var awakeMinutes: Double
    public var bedtime: Date?
    public var wakeTime: Date?
    public var qualityScore: Double
    public var primarySourceBundleId: String?
    public var primarySourceName: String?
    public var sessionCount: Int

    public static let empty = SleepNightResult(
        totalAsleepMinutes: 0,
        deepMinutes: 0,
        remMinutes: 0,
        coreMinutes: 0,
        awakeMinutes: 0,
        bedtime: nil,
        wakeTime: nil,
        qualityScore: 0,
        primarySourceBundleId: nil,
        primarySourceName: nil,
        sessionCount: 0
    )
}

// MARK: - Aggregator

/// Converts HealthKit sleep samples into one deduplicated night summary.
///
/// Design:
/// 1. Union overlapping *asleep* intervals across sleep sources (Watch + iPhone Sleep + sleep trackers).
/// 2. Ignore workout-only apps (e.g. Motra) if they ever appear on sleep samples.
/// 3. Detect sleep sessions (gap > 90 min) and pick the primary "last night" session.
/// 4. Stage breakdown comes from the single best source inside that session (prefers Apple stage data).
/// 5. `inBed` is used only when no asleep samples exist for the primary session.
public enum SleepNightAggregator {
    public static let sessionGapMinutes: Double = 90
    public static let queryLookbackHours: Int = 48

    public static func aggregate(
        samples: [SleepSampleInput],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SleepNightResult {
        guard !samples.isEmpty else { return .empty }

        let windowStart = calendar.date(byAdding: .hour, value: -queryLookbackHours, to: now) ?? now
        let clipped = samples.filter { sample in
            sample.end > windowStart
                && sample.start < now
                && !HealthSourceCatalog.isWorkoutOnlySource(sample.sourceBundleId)
        }
        guard !clipped.isEmpty else { return .empty }

        let asleepIntervals = clipped
            .filter { SleepCategoryValue.isAsleep($0.categoryValue) }
            .map { (start: max($0.start, windowStart), end: min($0.end, now)) }
            .filter { $0.end > $0.start }

        let mergedAsleep = mergeIntervals(asleepIntervals)

        if mergedAsleep.isEmpty {
            return aggregateInBedOnly(clipped: clipped, windowStart: windowStart, now: now)
        }

        let sessions = splitSessions(mergedAsleep, gapMinutes: sessionGapMinutes)
        guard let primary = selectPrimarySession(sessions, now: now, calendar: calendar) else {
            return .empty
        }

        let primarySource = selectBestStageSource(
            samples: clipped,
            session: primary
        )

        let stageTotals = stageMinutes(
            from: clipped,
            sourceBundleId: primarySource?.bundleId,
            session: primary
        )

        let awakeMinutes = mergedAwakeMinutes(
            samples: clipped,
            session: primary,
            sourceBundleId: primarySource?.bundleId
        )

        let totalAsleep = minutes(in: [primary])
        let quality = qualityScore(
            totalMinutes: totalAsleep,
            deepMinutes: stageTotals.deep,
            remMinutes: stageTotals.rem
        )

        return SleepNightResult(
            totalAsleepMinutes: totalAsleep,
            deepMinutes: stageTotals.deep,
            remMinutes: stageTotals.rem,
            coreMinutes: stageTotals.core,
            awakeMinutes: awakeMinutes,
            bedtime: primary.start,
            wakeTime: primary.end,
            qualityScore: quality,
            primarySourceBundleId: primarySource?.bundleId,
            primarySourceName: primarySource?.name,
            sessionCount: sessions.count
        )
    }

    // MARK: - Interval math

    static func mergeIntervals(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [(Date, Date)] = [(sorted[0].start, sorted[0].end)]

        for interval in sorted.dropFirst() {
            var last = merged[merged.count - 1]
            if interval.start <= last.1 {
                last.1 = max(last.1, interval.end)
                merged[merged.count - 1] = last
            } else {
                merged.append((interval.start, interval.end))
            }
        }
        return merged
    }

    static func minutes(in intervals: [(start: Date, end: Date)]) -> Double {
        intervals.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 60.0 }
    }

    static func splitSessions(
        _ merged: [(start: Date, end: Date)],
        gapMinutes: Double
    ) -> [(start: Date, end: Date)] {
        guard !merged.isEmpty else { return [] }
        var sessions: [(Date, Date)] = [merged[0]]
        let gapSeconds = gapMinutes * 60

        for interval in merged.dropFirst() {
            let last = sessions[sessions.count - 1]
            if interval.start.timeIntervalSince(last.1) > gapSeconds {
                sessions.append((interval.start, interval.end))
            } else {
                sessions[sessions.count - 1] = (last.0, max(last.1, interval.end))
            }
        }
        return sessions
    }

    static func selectPrimarySession(
        _ sessions: [(start: Date, end: Date)],
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        guard !sessions.isEmpty else { return nil }

        let todaySessions = sessions.filter { calendar.isDate($0.end, inSameDayAs: now) }
        if !todaySessions.isEmpty {
            return todaySessions.max(by: { minutes(in: [$0]) < minutes(in: [$1]) })
        }

        let hour = calendar.component(.hour, from: now)
        if hour < 12 {
            return sessions.max(by: { $0.end < $1.end })
        }

        return sessions.max(by: { minutes(in: [$0]) < minutes(in: [$1]) })
    }

    // MARK: - Source selection

    private struct SourceScore {
        var bundleId: String
        var name: String
        var score: Int
    }

    private static func selectBestStageSource(
        samples: [SleepSampleInput],
        session: (start: Date, end: Date)
    ) -> SourceScore? {
        let grouped = Dictionary(grouping: samples.filter {
            overlaps(session, start: $0.start, end: $0.end)
        }) { $0.sourceBundleId }

        let scored: [SourceScore] = grouped.map { bundleId, sourceSamples in
            let staged = sourceSamples.filter {
                SleepCategoryValue.isStagedAsleep($0.categoryValue)
            }
            let stagedMinutes = Int(staged.reduce(0.0) { $0 + clippedDuration($1, in: session) })
            let unspecified = sourceSamples.filter {
                $0.categoryValue == SleepCategoryValue.asleepUnspecified
            }
            let unspecifiedMinutes = Int(unspecified.reduce(0.0) { $0 + clippedDuration($1, in: session) })
            let priority = sourcePriority(bundleId)
            let score = priority + stagedMinutes * 3 + unspecifiedMinutes
            let name = sourceSamples.first?.sourceName ?? bundleId
            return SourceScore(bundleId: bundleId, name: name, score: score)
        }

        return scored.max(by: { $0.score < $1.score })
    }

    static func sourcePriority(_ bundleId: String) -> Int {
        let id = bundleId.lowercased()
        if id.hasPrefix("com.apple.") { return 1_000 }
        return 0
    }

    // MARK: - Stage / awake totals

    private struct StageTotals {
        var deep: Double = 0
        var rem: Double = 0
        var core: Double = 0
    }

    private static func stageMinutes(
        from samples: [SleepSampleInput],
        sourceBundleId: String?,
        session: (start: Date, end: Date)
    ) -> StageTotals {
        guard let sourceBundleId else { return StageTotals() }

        var deep: [(Date, Date)] = []
        var rem: [(Date, Date)] = []
        var core: [(Date, Date)] = []

        for sample in samples where sample.sourceBundleId == sourceBundleId {
            guard overlaps(session, start: sample.start, end: sample.end) else { continue }
            let clip = (
                start: max(sample.start, session.start),
                end: min(sample.end, session.end)
            )
            guard clip.end > clip.start else { continue }

            switch sample.categoryValue {
            case SleepCategoryValue.asleepDeep:
                deep.append(clip)
            case SleepCategoryValue.asleepREM:
                rem.append(clip)
            case SleepCategoryValue.asleepCore, SleepCategoryValue.asleepUnspecified:
                core.append(clip)
            default:
                break
            }
        }

        let mergedDeep = mergeIntervals(deep)
        let mergedREM = mergeIntervals(rem)
        let mergedCore = mergeIntervals(core)

        return StageTotals(
            deep: minutes(in: mergedDeep),
            rem: minutes(in: mergedREM),
            core: minutes(in: mergedCore)
        )
    }

    static func mergedAwakeMinutes(
        samples: [SleepSampleInput],
        session: (start: Date, end: Date),
        sourceBundleId: String?
    ) -> Double {
        let awakeSamples = samples.filter {
            $0.categoryValue == SleepCategoryValue.awake
                && overlaps(session, start: $0.start, end: $0.end)
                && (sourceBundleId == nil || $0.sourceBundleId == sourceBundleId)
        }
        let intervals = awakeSamples.map {
            (start: max($0.start, session.start), end: min($0.end, session.end))
        }.filter { $0.end > $0.start }
        return minutes(in: mergeIntervals(intervals))
    }

    // MARK: - inBed fallback

    static func aggregateInBedOnly(
        clipped: [SleepSampleInput],
        windowStart: Date,
        now: Date
    ) -> SleepNightResult {
        let inBed = clipped
            .filter { $0.categoryValue == SleepCategoryValue.inBed }
            .map { (start: max($0.start, windowStart), end: min($0.end, now)) }
            .filter { $0.end > $0.start }

        let merged = mergeIntervals(inBed)
        guard !merged.isEmpty else { return .empty }

        let sessions = splitSessions(merged, gapMinutes: sessionGapMinutes)
        guard let primary = selectPrimarySession(sessions, now: now, calendar: .current) else {
            return .empty
        }

        let total = minutes(in: [primary])
        let source = clipped.first { $0.categoryValue == SleepCategoryValue.inBed }

        return SleepNightResult(
            totalAsleepMinutes: total,
            deepMinutes: 0,
            remMinutes: 0,
            coreMinutes: total,
            awakeMinutes: 0,
            bedtime: primary.start,
            wakeTime: primary.end,
            qualityScore: qualityScore(totalMinutes: total, deepMinutes: 0, remMinutes: 0),
            primarySourceBundleId: source?.sourceBundleId,
            primarySourceName: source?.sourceName,
            sessionCount: sessions.count
        )
    }

    // MARK: - Helpers

    static func overlaps(_ session: (start: Date, end: Date), start: Date, end: Date) -> Bool {
        start < session.end && end > session.start
    }

    static func clippedDuration(_ sample: SleepSampleInput, in session: (start: Date, end: Date)) -> Double {
        let start = max(sample.start, session.start)
        let end = min(sample.end, session.end)
        guard end > start else { return 0 }
        return end.timeIntervalSince(start) / 60.0
    }

    static func qualityScore(totalMinutes: Double, deepMinutes: Double, remMinutes: Double) -> Double {
        guard totalMinutes > 0 else { return 0 }
        let deepRatio = deepMinutes / totalMinutes
        let remRatio = remMinutes / totalMinutes
        let durationScore = min(totalMinutes / 480.0, 1.0)
        return deepRatio * 0.3 + remRatio * 0.3 + durationScore * 0.4
    }
}

// MARK: - HK value constants (matches HealthKit raw values)

enum SleepCategoryValue {
    static let inBed = 0
    static let asleepUnspecified = 1
    static let awake = 2
    static let asleepCore = 3
    static let asleepDeep = 4
    static let asleepREM = 5

    static func isAsleep(_ value: Int) -> Bool {
        value == asleepUnspecified || value == asleepCore || value == asleepDeep || value == asleepREM
    }

    static func isStagedAsleep(_ value: Int) -> Bool {
        value == asleepCore || value == asleepDeep || value == asleepREM
    }
}
