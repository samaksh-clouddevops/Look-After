import Foundation
import LifeOSCore
import LifeOSAI

/// Background analytics orchestrator — batch-fetches once, updates incrementally, caches all timeframes.
@MainActor
public final class BackgroundAnalyticsService: ObservableObject {

    public static let shared = BackgroundAnalyticsService()

    public static let defaultLookbackDays = 90
    private static let minRefreshInterval: TimeInterval = 45

    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastRefreshAt: Date?
    @Published public private(set) var lastTrigger: AnalyticsRefreshTrigger?

    private let cacheManager = AnalyticsCacheManager.shared
    private let engine: PersonalAnalyticsEngine
    private let taskRepo: TaskRepository
    private let healthRepo: HealthSummaryRepository
    private let fetchBehaviorEvents: BehaviorEventsFetcher
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshAttempt: Date?

    public init(
        engine: PersonalAnalyticsEngine? = nil,
        taskRepo: TaskRepository? = nil,
        healthRepo: HealthSummaryRepository? = nil,
        fetchBehaviorEvents: @escaping BehaviorEventsFetcher = PersonalAnalyticsBehaviorLoader.fetchEvents
    ) {
        self.engine = engine ?? PersonalAnalyticsEngine(fetchBehaviorEvents: fetchBehaviorEvents)
        self.taskRepo = taskRepo ?? TaskRepository()
        self.healthRepo = healthRepo ?? HealthSummaryRepository()
        self.fetchBehaviorEvents = fetchBehaviorEvents
    }

    // MARK: - Instant reads (UI)

    public func cachedReport(timeframe: InsightsTimeframe, userId: String) -> PersonalAnalyticsReport? {
        cacheManager.cachedReport(timeframe: timeframe, userId: userId)
    }

    public func cachedAIContext(userId: String) -> CachedAIContextSummary? {
        cacheManager.cachedAIContext(userId: userId)
    }

    public func cachedWeeklyReport(userId: String) -> PersonalAnalyticsReport? {
        cachedReport(timeframe: .last7Days, userId: userId)
    }

    // MARK: - Background refresh

    public func scheduleRefresh(userId: String, trigger: AnalyticsRefreshTrigger, force: Bool = false) {
        guard !userId.isEmpty, !FreshInstallGuard.isActive else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshIfNeeded(userId: userId, trigger: trigger, force: force)
        }
    }

    public func refreshIfNeeded(userId: String, trigger: AnalyticsRefreshTrigger, force: Bool = false) async {
        guard !userId.isEmpty else { return }

        if !force,
           let last = lastRefreshAttempt,
           Date().timeIntervalSince(last) < Self.minRefreshInterval,
           cacheManager.cachedReport(timeframe: .last7Days, userId: userId) != nil {
            return
        }

        lastRefreshAttempt = Date()
        isRefreshing = true
        lastTrigger = trigger
        defer { isRefreshing = false }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        var state = cacheManager.cacheState(userId: userId) ?? AnalyticsCacheState(userId: userId)
        var snapshots = cacheManager.cachedSnapshots(userId: userId)

        // Single batch fetch — never repeated per timeframe
        let lookbackStart = calendar.date(byAdding: .day, value: -Self.defaultLookbackDays, to: today) ?? today
        let allTasks = (try? await taskRepo.getAll(for: userId)) ?? []
        let userTasks = allTasks.filter { !$0.userId.isEmpty ? $0.userId == userId : true }
        let healthSummaries = (try? await healthRepo.getForDateRange(from: lookbackStart, to: now, userId: userId)) ?? []
        let behaviorEvents = await fetchBehaviorEvents()
        let habitCompletions = Self.loadHabitCompletions()

        let taskFingerprint = userTasks.count
        let healthFingerprint = healthSummaries.count
        let behaviorFingerprint = behaviorEvents.count

        let dirtyKeys = Self.dirtyDayKeys(
            state: state,
            existingSnapshots: snapshots,
            calendar: calendar,
            today: today,
            lookbackDays: Self.defaultLookbackDays
        )

        let dataChanged = force
            || taskFingerprint != state.taskCountFingerprint
            || healthFingerprint != state.healthCountFingerprint
            || behaviorFingerprint != state.behaviorEventFingerprint
            || snapshots.isEmpty

        guard dataChanged else {
            lastRefreshAt = state.lastRefreshAt
            return
        }

        var snapshotMap = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })

        for key in dirtyKeys {
            guard let day = Self.date(from: key, calendar: calendar) else { continue }
            let snapshot = Self.buildSnapshot(
                for: day,
                userId: userId,
                calendar: calendar,
                healthSummaries: healthSummaries,
                userTasks: userTasks,
                behaviorEvents: behaviorEvents,
                habitCompletions: habitCompletions
            )
            snapshotMap[key] = snapshot
        }

        snapshots = snapshotMap.values.sorted { $0.date < $1.date }
        let overdueCount = userTasks.filter(\.isOverdue).count

        let reports = engine.buildAllReports(from: snapshots, userId: userId, overdueCount: overdueCount)
        let weeklyReport = reports[.last7Days]
        let aiContext = AIContextBuilder.build(snapshots: snapshots, weeklyReport: weeklyReport)

        state.userId = userId
        state.lastRefreshAt = now
        state.taskCountFingerprint = taskFingerprint
        state.healthCountFingerprint = healthFingerprint
        state.behaviorEventFingerprint = behaviorFingerprint
        state.processedDayKeys = snapshots.map(\.id)

        switch trigger {
        case .healthSyncCompleted: state.lastHealthSyncAt = now
        case .taskCompleted: state.lastTaskChangeAt = now
        case .habitChanged: state.lastHabitChangeAt = now
        default: break
        }

        var bundle = AnalyticsCacheBundle(state: state, snapshots: snapshots, aiContext: aiContext)
        for (timeframe, report) in reports {
            bundle.reports[timeframe.rawValue] = report
        }
        cacheManager.saveBundle(bundle, userId: userId)
        engine.invalidateCache()

        lastRefreshAt = now
    }

    public func invalidate(userId: String) {
        cacheManager.invalidate(userId: userId)
        engine.invalidateCache()
    }

    // MARK: - Incremental snapshot builder

    private static func buildSnapshot(
        for day: Date,
        userId: String,
        calendar: Calendar,
        healthSummaries: [HealthSummary],
        userTasks: [LifeTask],
        behaviorEvents: [BehaviorEvent],
        habitCompletions: [String: [String]]
    ) -> AnalyticsDailySnapshot {
        let dayStart = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let key = AnalyticsDailySnapshot.dayKey(for: dayStart, calendar: calendar)

        let health = healthSummaries.first { calendar.isDate($0.date, inSameDayAs: dayStart) }
        let tasksForDay = userTasks.filter {
            guard $0.status == .completed, let completedAt = $0.completedAt else { return false }
            return completedAt >= dayStart && completedAt < nextDay
        }
        let eventsForDay = behaviorEvents.filter { $0.recordedAt >= dayStart && $0.recordedAt < nextDay }

        let focusMinutes = focusMinutes(from: eventsForDay, completedTasks: tasksForDay)
        let habitCount = habitCompletions.values.filter { $0.contains(key) }.count

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

        return AnalyticsDailySnapshot(
            id: key,
            date: dayStart,
            userId: userId,
            sleepHours: health?.totalSleepMinutes.map { $0 / 60 },
            steps: health?.stepCount,
            hrv: health?.hrvAverage,
            restingHR: health?.restingHeartRate,
            energyScore: energyScore ?? health?.sleepQualityScore,
            efScore: efScore,
            tasksCompleted: tasksForDay.count,
            focusMinutes: focusMinutes,
            focusSessions: eventsForDay.filter { $0.kind == .flowSessionEnded }.count,
            habitCompletions: habitCount,
            lastUpdated: Date()
        )
    }

    private static func dirtyDayKeys(
        state: AnalyticsCacheState,
        existingSnapshots: [AnalyticsDailySnapshot],
        calendar: Calendar,
        today: Date,
        lookbackDays: Int
    ) -> Set<String> {
        var keys = Set<String>()
        let todayKey = AnalyticsDailySnapshot.dayKey(for: today, calendar: calendar)
        keys.insert(todayKey)

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            keys.insert(AnalyticsDailySnapshot.dayKey(for: yesterday, calendar: calendar))
        }

        if existingSnapshots.isEmpty {
            for offset in 0..<lookbackDays {
                if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                    keys.insert(AnalyticsDailySnapshot.dayKey(for: day, calendar: calendar))
                }
            }
        }

        return keys
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: key)
    }

    private static func focusMinutes(from events: [BehaviorEvent], completedTasks: [LifeTask]) -> Int {
        let sessionMinutes = events.filter { $0.kind == .flowSessionEnded }.compactMap(\.durationMinutes).reduce(0, +)
        if sessionMinutes > 0 { return sessionMinutes }
        let completionMinutes = events.filter { $0.kind == .taskCompletion }.compactMap(\.durationMinutes).reduce(0, +)
        if completionMinutes > 0 { return completionMinutes }
        return completedTasks.reduce(0) { $0 + $1.estimatedMinutes }
    }

    private static func loadHabitCompletions() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: "briefingHabitCompletions"),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var byHabit: [String: [String]] = [:]
        for (habitID, dateKey) in decoded {
            byHabit[habitID, default: []].append(dateKey)
        }
        return byHabit
    }

    /// Cancels in-flight refresh and clears session state after factory reset.
    public func resetForFactoryReset() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        lastRefreshAt = nil
        lastRefreshAttempt = nil
        lastTrigger = nil
    }
}
