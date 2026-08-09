import Foundation

// MARK: - High-load day tracking

/// Lightweight rolling window: a day is high-load when fluid minutes fall below a floor
/// relative to scheduled work. Feeds Sabotage Auction `consecutiveHighLoadDays`.
public enum HighLoadDayEvaluator {
    /// Below this fluid share of scheduled minutes → high-load day.
    public static let fluidShareFloor: Double = 0.12
    /// Absolute fluid minutes floor (whichever is more permissive for "high load").
    public static let absoluteFluidMinutesFloor: Int = 40
    /// Minimum scheduled minutes before the day counts (ignore empty days).
    public static let minScheduledMinutes: Int = 90

    public static func isHighLoadDay(
        tasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let dayTasks = tasks.filter { task in
            guard task.status.isActive || task.status == .completed else { return false }
            guard let d = task.scheduledDate, task.scheduledTime != nil else { return false }
            return calendar.isDate(d, inSameDayAs: dayStart)
        }
        guard !dayTasks.isEmpty else { return false }

        var scheduled = 0
        var fluid = 0
        for task in dayTasks {
            let mins = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            scheduled += mins
            if task.timeConstraintValue == .fluid || task.tags.contains("recovery-block") {
                fluid += mins
            }
        }
        guard scheduled >= minScheduledMinutes else { return false }

        let share = Double(fluid) / Double(scheduled)
        return share < fluidShareFloor && fluid < absoluteFluidMinutesFloor
    }

    /// Count consecutive high-load days ending yesterday (not including `now`'s incomplete day).
    public static func consecutiveHighLoadDays(
        tasks: [LifeTask],
        now: Date = Date(),
        lookback: Int = 5,
        calendar: Calendar = .current
    ) -> Int {
        var streak = 0
        let today = calendar.startOfDay(for: now)
        for offset in 1...lookback {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            if isHighLoadDay(tasks: tasks, on: day, calendar: calendar) {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    /// Longest run of high-load days inside the weekly review window.
    public static func maxConsecutiveHighLoadDays(
        inWeekEnding weekEnding: Date,
        tasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Int {
        let bounds = WeeklyReviewAggregator.weekBounds(ending: weekEnding, calendar: calendar)
        var maxStreak = 0
        var current = 0
        var day = bounds.start
        while day <= bounds.endInclusive {
            if isHighLoadDay(tasks: tasks, on: day, calendar: calendar) {
                current += 1
                maxStreak = max(maxStreak, current)
            } else {
                current = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return maxStreak
    }
}

// MARK: - Sabotage cool-down (Do Not Sabotage)

/// Suppresses Sabotage Auctions after the user overrides a recovery block.
public struct SabotagePolicyState: Codable, Sendable, Equatable {
    public var cooldownUntil: Date?
    public var lastOverrideAt: Date?
    public var overrideCount: Int

    public static let empty = SabotagePolicyState(cooldownUntil: nil, lastOverrideAt: nil, overrideCount: 0)

    public init(cooldownUntil: Date? = nil, lastOverrideAt: Date? = nil, overrideCount: Int = 0) {
        self.cooldownUntil = cooldownUntil
        self.lastOverrideAt = lastOverrideAt
        self.overrideCount = overrideCount
    }

    public func isCoolingDown(now: Date = Date()) -> Bool {
        guard let until = cooldownUntil else { return false }
        return now < until
    }
}

public final class SabotagePolicyStore: @unchecked Sendable {
    public static let shared = SabotagePolicyStore()
    public static let defaultCooldownDays = 7

    private let lock = NSLock()
    private var state: SabotagePolicyState
    private let fileURL: URL?
    private let memoryOnly: Bool

    public init(directory: URL? = nil) {
        memoryOnly = false
        if let directory {
            fileURL = directory.appendingPathComponent("sabotage_policy.json")
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            fileURL = support.appendingPathComponent("sabotage_policy.json")
        } else {
            fileURL = nil
        }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(SabotagePolicyState.self, from: data) {
            state = loaded
        } else {
            state = .empty
        }
    }

    public static func inMemory(state: SabotagePolicyState = .empty) -> SabotagePolicyStore {
        SabotagePolicyStore(memorySeed: state)
    }

    private init(memorySeed: SabotagePolicyState) {
        memoryOnly = true
        fileURL = nil
        state = memorySeed
    }

    public func current() -> SabotagePolicyState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public func isCoolingDown(now: Date = Date()) -> Bool {
        current().isCoolingDown(now: now)
    }

    /// User deleted/broke a recovery block — suppress auctions for `days`.
    public func recordSabotageOverride(now: Date = Date(), cooldownDays: Int = defaultCooldownDays) {
        lock.lock()
        let until = Calendar.current.date(byAdding: .day, value: cooldownDays, to: now)
        state.cooldownUntil = until
        state.lastOverrideAt = now
        state.overrideCount += 1
        let snap = state
        lock.unlock()
        persist(snap)
    }

    public func clearCooldown() {
        lock.lock()
        state.cooldownUntil = nil
        let snap = state
        lock.unlock()
        persist(snap)
    }

    private func persist(_ snap: SabotagePolicyState) {
        guard !memoryOnly, let fileURL else { return }
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
