import Foundation
import LookAfterCore

public protocol PersonalAnalyticsEngineProtocol: Sendable {
    func buildReport(timeframe: InsightsTimeframe, userId: String) async -> PersonalAnalyticsReport
}

public typealias BehaviorEventsFetcher = @Sendable () async -> [BehaviorEvent]

/// Aggregates HealthKit summaries, FlowOS tasks, focus sessions, and habits into real analytics.
@MainActor
public final class PersonalAnalyticsEngine: PersonalAnalyticsEngineProtocol {

    private let taskRepo: TaskRepository
    private let healthRepo: HealthSummaryRepository
    private let cognitiveModel: CognitiveModel
    private let fetchBehaviorEvents: BehaviorEventsFetcher
    private var cache: [String: PersonalAnalyticsReport] = [:]

    public init(
        taskRepo: TaskRepository? = nil,
        healthRepo: HealthSummaryRepository? = nil,
        cognitiveModel: CognitiveModel = CognitiveModel(),
        fetchBehaviorEvents: @escaping BehaviorEventsFetcher = { [] }
    ) {
        self.taskRepo = taskRepo ?? TaskRepository()
        self.healthRepo = healthRepo ?? HealthSummaryRepository()
        self.cognitiveModel = cognitiveModel
        self.fetchBehaviorEvents = fetchBehaviorEvents
    }

    public func buildReport(timeframe: InsightsTimeframe, userId: String) async -> PersonalAnalyticsReport {
        let cacheKey = "\(userId)-\(timeframe.rawValue)"
        if let cached = cache[cacheKey] {
            return cached
        }

        let calendar = Calendar.current
        let now = Date()
        let range = timeframe.dateRange(calendar: calendar, now: now)

        let allTasks = (try? await taskRepo.getAll(for: userId)) ?? []
        let userTasks = allTasks.filter { task in
            guard !userId.isEmpty else { return true }
            return task.userId == userId
        }
        let completedInRange = userTasks.filter { task in
            guard task.status == .completed, let completedAt = task.completedAt else { return false }
            return completedAt >= range.start && completedAt <= range.end
        }
        let overdueCount = userTasks.filter(\.isOverdue).count

        let healthSummaries = (try? await healthRepo.getForDateRange(from: range.start, to: range.end, userId: userId)) ?? []
        let behaviorEvents = await fetchBehaviorEvents()
        let eventsInRange = behaviorEvents.filter { $0.recordedAt >= range.start && $0.recordedAt <= range.end }

        let habitCompletions = Self.loadHabitCompletions()
        let buckets = Self.buildDailyBuckets(
            range: range,
            calendar: calendar,
            healthSummaries: healthSummaries,
            completedTasks: completedInRange,
            behaviorEvents: eventsInRange,
            habitCompletions: habitCompletions
        )

        let focusMinutes = Self.totalFocusMinutes(from: eventsInRange, completedTasks: completedInRange)
        let focusSessionCount = eventsInRange.filter { $0.kind == .flowSessionEnded }.count

        let avgSleep = Self.average(buckets.compactMap(\.sleepHours))
        let avgSteps = Self.averageInt(buckets.compactMap(\.steps))
        let avgHRV = Self.average(buckets.compactMap(\.hrv))
        let avgEnergy = Self.average(buckets.compactMap(\.energyScore))
        let avgEF = Self.averageInt(buckets.compactMap(\.efScore))

        let peakWindow = Self.peakProductivityWindow(
            completedTasks: completedInRange,
            behaviorEvents: eventsInRange,
            calendar: calendar
        )

        let habitAdherence = Self.habitAdherence(buckets: buckets, habitCount: BriefingHabitCatalog.count)

        let charts = Self.buildCharts(buckets: buckets, timeframe: timeframe, calendar: calendar)
        let categoryInsights = Self.buildCategoryInsights(
            buckets: buckets,
            avgSleep: avgSleep,
            avgSteps: avgSteps,
            avgHRV: avgHRV,
            completedCount: completedInRange.count,
            focusMinutes: focusMinutes,
            habitAdherence: habitAdherence
        )
        let correlations = Self.buildCorrelations(buckets: buckets, calendar: calendar)
            + Self.buildCycleCorrelations(buckets: buckets, calendar: calendar)
        let coachRecommendations = Self.buildCoachRecommendations(
            buckets: buckets,
            avgSleep: avgSleep,
            avgHRV: avgHRV,
            completedCount: completedInRange.count,
            focusMinutes: focusMinutes,
            habitAdherence: habitAdherence,
            peakWindow: peakWindow
        )
        let emptyStates = Self.buildEmptyStates(
            healthCount: healthSummaries.count,
            completedCount: completedInRange.count,
            focusSessionCount: focusSessionCount,
            hasHabitLogs: habitAdherence != nil
        )

        let hasData = completedInRange.count > 0
            || !healthSummaries.isEmpty
            || focusSessionCount > 0
            || (habitAdherence ?? 0) > 0

        let kpis = PersonalAnalyticsKPIs(
            totalFocusMinutes: focusMinutes > 0 ? focusMinutes : nil,
            completedTasksCount: completedInRange.count > 0 ? completedInRange.count : nil,
            averageEnergyScore: avgEnergy,
            averageExecutiveFunctionScore: avgEF,
            peakProductivityWindow: peakWindow,
            averageSleepHours: avgSleep,
            averageSteps: avgSteps,
            averageHRV: avgHRV,
            habitAdherencePercent: habitAdherence,
            overdueTasksCount: overdueCount > 0 ? overdueCount : nil,
            focusSessionCount: focusSessionCount > 0 ? focusSessionCount : nil
        )

        let promptContext = Self.buildPersonalizationContext(
            timeframe: timeframe,
            kpis: kpis,
            correlations: correlations,
            coachRecommendations: coachRecommendations
        )

        let report = PersonalAnalyticsReport(
            timeframe: timeframe,
            generatedAt: now,
            userId: userId,
            kpis: kpis,
            charts: charts,
            insights: categoryInsights,
            correlations: correlations,
            coachRecommendations: coachRecommendations,
            emptyStateMessages: emptyStates,
            personalizationPromptContext: promptContext,
            hasSufficientData: hasData
        )

        cache[cacheKey] = report
        return report
    }

    public func invalidateCache() {
        cache.removeAll()
    }

    /// Fast path: assemble a report from precomputed daily snapshots (no repository I/O).
    public func buildReport(
        from snapshots: [AnalyticsDailySnapshot],
        timeframe: InsightsTimeframe,
        userId: String,
        overdueCount: Int = 0
    ) -> PersonalAnalyticsReport {
        let calendar = Calendar.current
        let now = Date()
        let range = timeframe.dateRange(calendar: calendar, now: now)

        let buckets = snapshots
            .filter { $0.date >= range.start && $0.date <= range.end }
            .sorted { $0.date < $1.date }
            .map { snapshot in
                DayBucket(
                    date: snapshot.date,
                    sleepHours: snapshot.sleepHours,
                    steps: snapshot.steps,
                    hrv: snapshot.hrv,
                    restingHR: snapshot.restingHR,
                    energyScore: snapshot.energyScore,
                    efScore: snapshot.efScore,
                    tasksCompleted: snapshot.tasksCompleted,
                    focusMinutes: snapshot.focusMinutes,
                    habitCompletions: snapshot.habitCompletions,
                    focusSessions: snapshot.focusSessions
                )
            }

        let healthCount = snapshots.filter { $0.sleepHours != nil || $0.steps != nil }.count
        let completedCount = buckets.reduce(0) { $0 + $1.tasksCompleted }
        let focusSessionCount = buckets.reduce(0) { $0 + $1.focusSessions }

        return assembleReport(
            buckets: buckets,
            timeframe: timeframe,
            userId: userId,
            overdueCount: overdueCount,
            healthCount: healthCount,
            completedCount: completedCount,
            focusSessionCount: focusSessionCount,
            generatedAt: now
        )
    }

    /// Builds reports for all standard timeframes from snapshots in one pass.
    public func buildAllReports(
        from snapshots: [AnalyticsDailySnapshot],
        userId: String,
        overdueCount: Int = 0
    ) -> [InsightsTimeframe: PersonalAnalyticsReport] {
        var reports: [InsightsTimeframe: PersonalAnalyticsReport] = [:]
        for timeframe in InsightsTimeframe.allCases {
            reports[timeframe] = buildReport(from: snapshots, timeframe: timeframe, userId: userId, overdueCount: overdueCount)
        }
        return reports
    }

    private func assembleReport(
        buckets: [DayBucket],
        timeframe: InsightsTimeframe,
        userId: String,
        overdueCount: Int,
        healthCount: Int,
        completedCount: Int,
        focusSessionCount: Int,
        generatedAt: Date
    ) -> PersonalAnalyticsReport {
        let calendar = Calendar.current

        let focusMinutes = buckets.reduce(0) { $0 + $1.focusMinutes }
        let avgSleep = Self.average(buckets.compactMap(\.sleepHours))
        let avgSteps = Self.averageInt(buckets.compactMap(\.steps))
        let avgHRV = Self.average(buckets.compactMap(\.hrv))
        let avgEnergy = Self.average(buckets.compactMap(\.energyScore))
        let avgEF = Self.averageInt(buckets.compactMap(\.efScore))

        let peakWindow = Self.peakProductivityWindowFromBuckets(buckets, calendar: calendar)
        let habitAdherence = Self.habitAdherence(buckets: buckets, habitCount: BriefingHabitCatalog.count)

        let charts = Self.buildCharts(buckets: buckets, timeframe: timeframe, calendar: calendar)
        let categoryInsights = Self.buildCategoryInsights(
            buckets: buckets,
            avgSleep: avgSleep,
            avgSteps: avgSteps,
            avgHRV: avgHRV,
            completedCount: completedCount,
            focusMinutes: focusMinutes,
            habitAdherence: habitAdherence
        )
        let correlations = Self.buildCorrelations(buckets: buckets, calendar: calendar)
            + Self.buildCycleCorrelations(buckets: buckets, calendar: calendar)
        let coachRecommendations = Self.buildCoachRecommendations(
            buckets: buckets,
            avgSleep: avgSleep,
            avgHRV: avgHRV,
            completedCount: completedCount,
            focusMinutes: focusMinutes,
            habitAdherence: habitAdherence,
            peakWindow: peakWindow
        )
        let emptyStates = Self.buildEmptyStates(
            healthCount: healthCount,
            completedCount: completedCount,
            focusSessionCount: focusSessionCount,
            hasHabitLogs: habitAdherence != nil
        )

        let hasData = completedCount > 0
            || healthCount > 0
            || focusSessionCount > 0
            || (habitAdherence ?? 0) > 0

        let kpis = PersonalAnalyticsKPIs(
            totalFocusMinutes: focusMinutes > 0 ? focusMinutes : nil,
            completedTasksCount: completedCount > 0 ? completedCount : nil,
            averageEnergyScore: avgEnergy,
            averageExecutiveFunctionScore: avgEF,
            peakProductivityWindow: peakWindow,
            averageSleepHours: avgSleep,
            averageSteps: avgSteps,
            averageHRV: avgHRV,
            habitAdherencePercent: habitAdherence,
            overdueTasksCount: overdueCount > 0 ? overdueCount : nil,
            focusSessionCount: focusSessionCount > 0 ? focusSessionCount : nil
        )

        let promptContext = Self.buildPersonalizationContext(
            timeframe: timeframe,
            kpis: kpis,
            correlations: correlations,
            coachRecommendations: coachRecommendations
        )

        return PersonalAnalyticsReport(
            timeframe: timeframe,
            generatedAt: generatedAt,
            userId: userId,
            kpis: kpis,
            charts: charts,
            insights: categoryInsights,
            correlations: correlations,
            coachRecommendations: coachRecommendations,
            emptyStateMessages: emptyStates,
            personalizationPromptContext: promptContext,
            hasSufficientData: hasData
        )
    }

    private static func peakProductivityWindowFromBuckets(_ buckets: [DayBucket], calendar: Calendar) -> String? {
        var hourCounts: [Int: Int] = [:]
        for bucket in buckets where bucket.tasksCompleted > 0 {
            let hour = calendar.component(.hour, from: bucket.date)
            hourCounts[hour, default: 0] += bucket.tasksCompleted
        }
        guard let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key else { return nil }
        return "\(formatHour(peakHour)) – \(formatHour(min(peakHour + 2, 23)))"
    }

    struct DayBucket {
        var date: Date
        var sleepHours: Double?
        var steps: Int?
        var hrv: Double?
        var restingHR: Double?
        var energyScore: Double?
        var efScore: Int?
        var tasksCompleted: Int
        var focusMinutes: Int
        var habitCompletions: Int
        var focusSessions: Int
    }

    private static func buildDailyBuckets(
        range: (start: Date, end: Date),
        calendar: Calendar,
        healthSummaries: [HealthSummary],
        completedTasks: [LifeTask],
        behaviorEvents: [BehaviorEvent],
        habitCompletions: [String: [String]]
    ) -> [DayBucket] {
        var buckets: [DayBucket] = []
        var day = calendar.startOfDay(for: range.start)
        let endDay = calendar.startOfDay(for: range.end)

        while day <= endDay {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let health = healthSummaries.first { calendar.isDate($0.date, inSameDayAs: day) }
            let tasksForDay = completedTasks.filter {
                guard let completedAt = $0.completedAt else { return false }
                return completedAt >= day && completedAt < nextDay
            }
            let eventsForDay = behaviorEvents.filter { $0.recordedAt >= day && $0.recordedAt < nextDay }
            let focusMinutes = totalFocusMinutes(from: eventsForDay, completedTasks: tasksForDay)
            let habitCount = habitCompletions.values.filter { dates in
                dates.contains(dayKey(for: day))
            }.count

            var efScore: Int?
            var energyScore: Double?
            if let health {
                let snapshot = CognitiveModel().generateSnapshot(
                    healthSummary: health,
                    recentEnergyReports: [],
                    completedTasksToday: tasksForDay,
                    profile: UserLifeProfileStore.loadUserProfile()
                )
                efScore = snapshot.executiveFunctionScore
                energyScore = snapshot.energyScore
            }

            buckets.append(DayBucket(
                date: day,
                sleepHours: health?.totalSleepMinutes.map { $0 / 60 },
                steps: health?.stepCount,
                hrv: health?.hrvAverage,
                restingHR: health?.restingHeartRate,
                energyScore: energyScore ?? health?.sleepQualityScore,
                efScore: efScore,
                tasksCompleted: tasksForDay.count,
                focusMinutes: focusMinutes,
                habitCompletions: habitCount,
                focusSessions: eventsForDay.filter { $0.kind == .flowSessionEnded }.count
            ))

            day = nextDay
        }

        return buckets
    }

    // MARK: - KPI helpers

    private static func totalFocusMinutes(from events: [BehaviorEvent], completedTasks: [LifeTask]) -> Int {
        let sessionMinutes = events
            .filter { $0.kind == .flowSessionEnded }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
        if sessionMinutes > 0 { return sessionMinutes }

        let completionMinutes = events
            .filter { $0.kind == .taskCompletion }
            .compactMap(\.durationMinutes)
            .reduce(0, +)
        if completionMinutes > 0 { return completionMinutes }

        return completedTasks.reduce(0) { $0 + $1.estimatedMinutes }
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private static func peakProductivityWindow(
        completedTasks: [LifeTask],
        behaviorEvents: [BehaviorEvent],
        calendar: Calendar
    ) -> String? {
        var hourCounts: [Int: Int] = [:]

        for task in completedTasks {
            guard let completedAt = task.completedAt else { continue }
            let hour = calendar.component(.hour, from: completedAt)
            hourCounts[hour, default: 0] += 1
        }

        for event in behaviorEvents where event.kind == .taskCompletion || event.kind == .flowSessionEnded {
            let hour = event.context.hourOfDay
            hourCounts[hour, default: 0] += 1
        }

        guard let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key else { return nil }
        let start = formatHour(peakHour)
        let end = formatHour(min(peakHour + 2, 23))
        return "\(start) – \(end)"
    }

    private static func habitAdherence(buckets: [DayBucket], habitCount: Int) -> Int? {
        guard habitCount > 0, !buckets.isEmpty else { return nil }
        let possible = buckets.count * habitCount
        let completed = buckets.reduce(0) { $0 + $1.habitCompletions }
        guard possible > 0 else { return nil }
        return Int((Double(completed) / Double(possible)) * 100)
    }

    // MARK: - Charts

    private static func buildCharts(
        buckets: [DayBucket],
        timeframe: InsightsTimeframe,
        calendar: Calendar
    ) -> [AnalyticsChartSeries] {
        let formatter = DateFormatter()
        formatter.dateFormat = timeframe.dayCount > 30 ? "M/d" : "EEE"

        func points(for value: (DayBucket) -> Double?) -> [AnalyticsTrendPoint] {
            buckets.enumerated().map { index, bucket in
                AnalyticsTrendPoint(
                    id: "\(index)",
                    label: formatter.string(from: bucket.date),
                    value: value(bucket) ?? 0,
                    date: bucket.date
                )
            }
        }

        let sleepValues = buckets.compactMap(\.sleepHours)
        let stepValues = buckets.compactMap(\.steps)
        let taskValues = buckets.map { Double($0.tasksCompleted) }
        let focusValues = buckets.map { Double($0.focusMinutes) }
        let habitValues = buckets.map { Double($0.habitCompletions) }
        let energyValues = buckets.compactMap(\.energyScore)
        let hrvValues = buckets.compactMap(\.hrv)

        return [
            AnalyticsChartSeries(
                metric: .sleep,
                points: points { $0.sleepHours },
                unit: "h",
                hasData: !sleepValues.isEmpty
            ),
            AnalyticsChartSeries(
                metric: .energy,
                points: points { $0.energyScore.map { $0 * 100 } },
                unit: "%",
                hasData: !energyValues.isEmpty
            ),
            AnalyticsChartSeries(
                metric: .steps,
                points: points { $0.steps.map(Double.init) },
                unit: "steps",
                hasData: !stepValues.isEmpty
            ),
            AnalyticsChartSeries(
                metric: .taskCompletion,
                points: points { Double($0.tasksCompleted) },
                unit: "tasks",
                hasData: taskValues.contains(where: { $0 > 0 })
            ),
            AnalyticsChartSeries(
                metric: .focusSessions,
                points: points { Double($0.focusMinutes) },
                unit: "min",
                hasData: focusValues.contains(where: { $0 > 0 })
            ),
            AnalyticsChartSeries(
                metric: .habitCompletion,
                points: points { Double($0.habitCompletions) },
                unit: "habits",
                hasData: habitValues.contains(where: { $0 > 0 })
            ),
            AnalyticsChartSeries(
                metric: .hrv,
                points: points { $0.hrv },
                unit: "ms",
                hasData: !hrvValues.isEmpty
            ),
        ]
    }

    // MARK: - Insights & correlations

    private static func buildCategoryInsights(
        buckets: [DayBucket],
        avgSleep: Double?,
        avgSteps: Int?,
        avgHRV: Double?,
        completedCount: Int,
        focusMinutes: Int,
        habitAdherence: Int?
    ) -> [AnalyticsInsight] {
        var results: [AnalyticsInsight] = []

        if let avgSleep {
            results.append(AnalyticsInsight(
                category: .sleep,
                message: String(format: "Average sleep: %.1f hours over this period.", avgSleep)
            ))
        }

        if let avgSteps {
            results.append(AnalyticsInsight(
                category: .health,
                message: "Daily step average: \(avgSteps.formatted())."
            ))
        }

        if let avgHRV {
            results.append(AnalyticsInsight(
                category: .health,
                message: String(format: "Average HRV: %.0f ms.", avgHRV)
            ))
        }

        if completedCount > 0 {
            let perDay = Double(completedCount) / Double(max(buckets.count, 1))
            results.append(AnalyticsInsight(
                category: .productivity,
                message: String(format: "Completed %.1f tasks per day on average.", perDay)
            ))
        }

        if focusMinutes > 0 {
            results.append(AnalyticsInsight(
                category: .productivity,
                message: "Logged \(focusMinutes / 60)h \(focusMinutes % 60)m on timed sessions."
            ))
        }

        if let habitAdherence {
            results.append(AnalyticsInsight(
                category: .habits,
                message: "Habit adherence: \(habitAdherence)% over this period."
            ))
        }

        return results
    }

    private static func buildCorrelations(
        buckets: [DayBucket],
        calendar: Calendar
    ) -> [AnalyticsInsight] {
        var results: [AnalyticsInsight] = []

        let goodSleep = buckets.filter { ($0.sleepHours ?? 0) >= 7.5 }
        let poorSleep = buckets.filter { ($0.sleepHours ?? 0) > 0 && ($0.sleepHours ?? 0) < 7.5 }

        if goodSleep.count >= 2, poorSleep.count >= 2 {
            let goodAvg = Double(goodSleep.map(\.tasksCompleted).reduce(0, +)) / Double(goodSleep.count)
            let poorAvg = Double(poorSleep.map(\.tasksCompleted).reduce(0, +)) / Double(poorSleep.count)
            if goodAvg > poorAvg + 0.5 {
                results.append(AnalyticsInsight(
                    category: .correlation,
                    message: String(format: "Better sleep leads to more completed tasks: %.1f vs %.1f tasks/day on ≥7.5h vs <7.5h sleep nights.", goodAvg, poorAvg)
                ))
            }
        }

        let highHRV = buckets.filter { ($0.hrv ?? 0) >= 40 }
        let lowHRV = buckets.filter { ($0.hrv ?? 0) > 0 && ($0.hrv ?? 0) < 40 }
        if highHRV.count >= 2, lowHRV.count >= 2 {
            let highFocus = Double(highHRV.map(\.focusMinutes).reduce(0, +)) / Double(highHRV.count)
            let lowFocus = Double(lowHRV.map(\.focusMinutes).reduce(0, +)) / Double(lowHRV.count)
            if highFocus > lowFocus + 5 {
                results.append(AnalyticsInsight(
                    category: .correlation,
                    message: String(format: "Higher HRV correlates with more uninterrupted time (%.0f vs %.0f min/day).", highFocus, lowFocus)
                ))
            }
        }

        let activeDays = buckets.filter { ($0.steps ?? 0) >= 5_000 }
        let sedentaryDays = buckets.filter { ($0.steps ?? 0) > 0 && ($0.steps ?? 0) < 5_000 }
        if activeDays.count >= 2, sedentaryDays.count >= 2 {
            let activeTasks = Double(activeDays.map(\.tasksCompleted).reduce(0, +)) / Double(activeDays.count)
            let sedentaryTasks = Double(sedentaryDays.map(\.tasksCompleted).reduce(0, +)) / Double(sedentaryDays.count)
            if activeTasks > sedentaryTasks + 0.5 {
                results.append(AnalyticsInsight(
                    category: .correlation,
                    message: String(format: "Exercise days (5k+ steps) have better task completion (%.1f vs %.1f tasks/day).", activeTasks, sedentaryTasks)
                ))
            }
        }

        var weekdayTasks: [Int: [Int]] = [:]
        for bucket in buckets where bucket.tasksCompleted > 0 {
            let weekday = calendar.component(.weekday, from: bucket.date)
            weekdayTasks[weekday, default: []].append(bucket.tasksCompleted)
        }
        if let bestDay = weekdayTasks.max(by: { lhs, rhs in
            Double(lhs.value.reduce(0, +)) / Double(lhs.value.count) < Double(rhs.value.reduce(0, +)) / Double(rhs.value.count)
        }) {
            let avg = Double(bestDay.value.reduce(0, +)) / Double(bestDay.value.count)
            let name = calendar.weekdaySymbols[bestDay.key - 1]
            results.append(AnalyticsInsight(
                category: .correlation,
                message: String(format: "%@s are when you finish the most tasks (%.1f tasks/day).", name, avg)
            ))
        }

        return results
    }

    private static func buildCycleCorrelations(
        buckets: [DayBucket],
        calendar: Calendar
    ) -> [AnalyticsInsight] {
        guard CycleFeatureGate.isActive else { return [] }
        var results: [AnalyticsInsight] = []

        let logs = CycleLogStore.load()
        guard !logs.isEmpty || CyclePreferencesStore.load().lastPeriodStart != nil else { return [] }

        var lutealTasks: [Int] = []
        var follicularTasks: [Int] = []
        var lutealSleep: [Double] = []
        var follicularSleep: [Double] = []
        var lowEnergyByPhase: [CyclePhase: Int] = [:]
        var loggedByPhase: [CyclePhase: Int] = [:]

        for bucket in buckets {
            let snapshot = CycleEngine.snapshot(
                CycleEngine.Input(logs: logs, now: bucket.date, calendar: calendar)
            )
            guard snapshot.isEnabled, snapshot.phase != .unknown else { continue }

            switch snapshot.phase {
            case .luteal, .menstrual:
                if bucket.tasksCompleted > 0 { lutealTasks.append(bucket.tasksCompleted) }
                if let sleep = bucket.sleepHours, sleep > 0 { lutealSleep.append(sleep) }
            case .follicular, .ovulation:
                if bucket.tasksCompleted > 0 { follicularTasks.append(bucket.tasksCompleted) }
                if let sleep = bucket.sleepHours, sleep > 0 { follicularSleep.append(sleep) }
            case .unknown:
                break
            }
        }

        for log in logs {
            let snapshot = CycleEngine.snapshot(
                CycleEngine.Input(logs: logs, now: log.day, calendar: calendar)
            )
            guard snapshot.phase != .unknown else { continue }
            loggedByPhase[snapshot.phase, default: 0] += 1
            if let energy = log.energy, energy <= 2 {
                lowEnergyByPhase[snapshot.phase, default: 0] += 1
            }
        }

        if lutealTasks.count >= 2, follicularTasks.count >= 2 {
            let lutealAvg = Double(lutealTasks.reduce(0, +)) / Double(lutealTasks.count)
            let follicularAvg = Double(follicularTasks.reduce(0, +)) / Double(follicularTasks.count)
            if follicularAvg > lutealAvg + 0.5 {
                results.append(AnalyticsInsight(
                    category: .correlation,
                    message: String(format: "Task completion tends to be higher in follicular/ovulation days (%.1f vs %.1f tasks/day in luteal/menstrual).", follicularAvg, lutealAvg)
                ))
            } else if lutealAvg > follicularAvg + 0.5 {
                results.append(AnalyticsInsight(
                    category: .correlation,
                    message: String(format: "You finish more tasks during luteal/menstrual days (%.1f vs %.1f tasks/day) — your pattern differs from typical.", lutealAvg, follicularAvg)
                ))
            }
        }

        if lutealSleep.count >= 2, follicularSleep.count >= 2 {
            let lutealAvg = lutealSleep.reduce(0, +) / Double(lutealSleep.count)
            let follicularAvg = follicularSleep.reduce(0, +) / Double(follicularSleep.count)
            if lutealAvg + 0.3 < follicularAvg {
                results.append(AnalyticsInsight(
                    category: .correlation,
                    message: String(format: "Sleep averages lower during luteal/menstrual phase (%.1fh vs %.1fh).", lutealAvg, follicularAvg)
                ))
            }
        }

        if let phase = lowEnergyByPhase.max(by: { $0.value < $1.value }),
           phase.value >= 2,
           loggedByPhase[phase.key, default: 0] >= 2 {
            results.append(AnalyticsInsight(
                category: .correlation,
                message: "Low energy logs cluster in \(phase.key.displayLabel.lowercased()) phase (\(phase.value) times) — plan lighter work then."
            ))
        }

        let symptomPatterns = CycleEngine.symptomFrequencyByPhase(
            input: CycleEngine.Input(logs: logs, calendar: calendar)
        )
        for (phase, symptoms) in symptomPatterns {
            if let top = symptoms.max(by: { $0.value < $1.value }), top.value >= 2 {
                results.append(AnalyticsInsight(
                    category: .correlation,
                    message: "\(top.key) shows up most often in \(phase.displayLabel.lowercased()) phase (\(top.value) logs)."
                ))
            }
        }

        return results
    }

    private static func buildCoachRecommendations(
        buckets: [DayBucket],
        avgSleep: Double?,
        avgHRV: Double?,
        completedCount: Int,
        focusMinutes: Int,
        habitAdherence: Int?,
        peakWindow: String?
    ) -> [AnalyticsInsight] {
        var results: [AnalyticsInsight] = []

        if let avgSleep, avgSleep >= 7.5, completedCount > 0 {
            results.append(AnalyticsInsight(
                category: .coach,
                message: String(format: "You average %.1fh of sleep — protect this rhythm; it's supporting %.0f completed tasks this period.", avgSleep, Double(completedCount))
            ))
        } else if let avgSleep, avgSleep < 7 {
            results.append(AnalyticsInsight(
                category: .coach,
                message: String(format: "Sleep is averaging %.1fh. Prioritize recovery — your task output may improve with more rest.", avgSleep)
            ))
        }

        if let peakWindow {
            results.append(AnalyticsInsight(
                category: .coach,
                message: "You finish the most tasks around \(peakWindow)."
            ))
        }

        if let avgHRV, buckets.count >= 14 {
            let recent = buckets.suffix(7).compactMap(\.hrv)
            let prior = buckets.dropLast(7).suffix(7).compactMap(\.hrv)
            if recent.count >= 3, prior.count >= 3 {
                let recentAvg = recent.reduce(0, +) / Double(recent.count)
                let priorAvg = prior.reduce(0, +) / Double(prior.count)
                if priorAvg > 0 {
                    let change = ((recentAvg - priorAvg) / priorAvg) * 100
                    if abs(change) >= 5 {
                        let direction = change > 0 ? "improved" : "declined"
                        results.append(AnalyticsInsight(
                            category: .coach,
                            message: String(format: "Your average HRV has %@ by %.0f%% over the last two weeks.", direction, abs(change))
                        ))
                    }
                }
            }
        }

        if focusMinutes == 0, completedCount > 0 {
            results.append(AnalyticsInsight(
                category: .coach,
                message: "Try using the timer — it helps correlate energy with when you actually finish tasks."
            ))
        }

        if let habitAdherence, habitAdherence < 50 {
            results.append(AnalyticsInsight(
                category: .coach,
                message: "Habit adherence is \(habitAdherence)%. Consider reducing to 2–3 core habits to rebuild consistency."
            ))
        }

        return results
    }

    private static func buildEmptyStates(
        healthCount: Int,
        completedCount: Int,
        focusSessionCount: Int,
        hasHabitLogs: Bool
    ) -> [String] {
        var messages: [String] = []

        if healthCount == 0 {
            messages.append("Not enough sleep history yet. Connect Apple Health and sync your Watch.")
        }
        if completedCount == 0 {
            messages.append("Complete tasks to unlock more patterns.")
        }
        if focusSessionCount == 0 {
            messages.append("Use the timer to see when you work best.")
        }
        if !hasHabitLogs {
            messages.append("Log habits on the Daily Briefing to see adherence trends.")
        }

        return messages
    }

    private static func buildPersonalizationContext(
        timeframe: InsightsTimeframe,
        kpis: PersonalAnalyticsKPIs,
        correlations: [AnalyticsInsight],
        coachRecommendations: [AnalyticsInsight]
    ) -> String {
        var lines = ["USER ANALYTICS (\(timeframe.rawValue)) — real data only:"]

        if let focus = kpis.totalFocusMinutes {
            lines.append("- Focus time: \(focus / 60)h \(focus % 60)m")
        }
        if let tasks = kpis.completedTasksCount {
            lines.append("- Tasks completed: \(tasks)")
        }
        if let energy = kpis.averageEnergyScore {
            lines.append("- Avg energy: \(Int(energy * 100))%")
        }
        if let ef = kpis.averageExecutiveFunctionScore {
            lines.append("- EF index: \(ef)/100")
        }
        if let sleep = kpis.averageSleepHours {
            lines.append("- Avg sleep: \(String(format: "%.1f", sleep))h")
        }
        if let peak = kpis.peakProductivityWindow {
            lines.append("- Peak window: \(peak)")
        }

        let patterns = (correlations + coachRecommendations).map(\.message)
        if !patterns.isEmpty {
            lines.append("- Patterns: \(patterns.joined(separator: "; "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Habits storage

    enum BriefingHabitCatalog {
        static let count = 6
        static let storageKey = "briefingHabitCompletions"
    }

    private static func loadHabitCompletions() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: BriefingHabitCatalog.storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        var byHabit: [String: [String]] = [:]
        for (habitID, dateKey) in decoded {
            byHabit[habitID, default: []].append(dateKey)
        }
        return byHabit
    }

    private static func dayKey(for date: Date) -> String {
        ISO8601DateFormatter().string(from: date).prefix(10).description
    }

    private static func formatHour(_ hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        let suffix = normalized >= 12 ? "PM" : "AM"
        let display = normalized % 12 == 0 ? 12 : normalized % 12
        return "\(display):00 \(suffix)"
    }
}

/// Loads behavior events from the on-device behavior memory file.
public enum PersonalAnalyticsBehaviorLoader {
    public static func fetchEvents() async -> [BehaviorEvent] {
        let backend = FileBehaviorMemoryPersistenceBackend()
        let store = await BehaviorMemoryStore(backend: backend)
        return await store.fetchEvents()
    }
}
