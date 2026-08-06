import Foundation

// MARK: - Auction context

/// Biometric / circadian context for gap auctions — pure values, no HealthKit import.
public struct GapAuctionContext: Sendable, Equatable {
    public var energy: EnergyLevel
    public var hour: Int
    public var weekday: Int
    /// Rolling count of consecutive high-capacity days (≥4h scheduled, few fluid gaps).
    public var consecutiveHighLoadDays: Int
    public var gapMinutes: Int
    public var now: Date
    /// When true, sabotage is suppressed (user recently overrode a recovery lock).
    public var sabotageCooldownActive: Bool

    public init(
        energy: EnergyLevel = .moderate,
        hour: Int? = nil,
        weekday: Int? = nil,
        consecutiveHighLoadDays: Int = 0,
        gapMinutes: Int,
        now: Date = Date(),
        sabotageCooldownActive: Bool = false,
        calendar: Calendar = .current
    ) {
        self.energy = energy
        self.hour = hour ?? calendar.component(.hour, from: now)
        self.weekday = weekday ?? calendar.component(.weekday, from: now)
        self.consecutiveHighLoadDays = consecutiveHighLoadDays
        self.gapMinutes = gapMinutes
        self.now = now
        self.sabotageCooldownActive = sabotageCooldownActive
    }

    public var timeOfDay: BehavioralTimeOfDay {
        BehavioralTimeOfDay.from(hour: hour)
    }

    public var isFridayAfternoon: Bool {
        // Gregorian: Sunday=1 … Friday=6
        weekday == 6 && hour >= 15
    }

    public var isLowEnergyWindow: Bool {
        energy == .low || energy == .recovery || hour >= 16 || isFridayAfternoon
    }

    /// Sabotage: force recovery when redlining — unless user opted out via cooldown.
    public var shouldForceRecoveryBlock: Bool {
        !sabotageCooldownActive
            && consecutiveHighLoadDays >= 5
            && gapMinutes >= 45
            && gapMinutes <= 180
    }
}

// MARK: - Auction outcome

public enum GapAuctionOutcome: Sendable, Equatable {
    /// Intentionally empty — locked recovery block.
    case sabotageRecovery(reason: String)
    /// Ranked winners to place into the gap.
    case filled(winners: [ParkedTaskEntry])
    case empty
}

// MARK: - Engine

public enum GapAuctionEngine {

    /// Deep / heavy work areas (penalized in low-energy windows).
    private static let heavyAreas: Set<LifeArea> = [.work, .creativity, .learning]
    private static let lightAreas: Set<LifeArea> = [.home, .shopping, .personal, .health, .reflection]

    public static func run(
        pool: [ParkedTaskEntry],
        context: GapAuctionContext,
        limit: Int = 3
    ) -> GapAuctionOutcome {
        if context.shouldForceRecoveryBlock {
            return .sabotageRecovery(reason: "consecutive_high_load_\(context.consecutiveHighLoadDays)d")
        }

        let scored: [(ParkedTaskEntry, Double)] = pool.compactMap { entry in
            guard entry.decayState == .recoverable else { return nil }
            guard entry.originalDurationMinutes <= context.gapMinutes + 10 else { return nil }
            return (entry, score(entry, context: context))
        }

        let winners = scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)

        return winners.isEmpty ? .empty : .filled(winners: Array(winners))
    }

    public static func score(_ entry: ParkedTaskEntry, context: GapAuctionContext) -> Double {
        var score = 0.0
        score += min(entry.ageDays(now: context.now), 14) * 2
        score += Double(entry.priority.rawValue) * 8
        let waste = max(0, context.gapMinutes - entry.originalDurationMinutes)
        score += max(0, 30 - Double(waste))

        // Energy × area
        switch context.energy {
        case .peak, .high:
            if heavyAreas.contains(entry.lifeArea) { score += 14 }
            if lightAreas.contains(entry.lifeArea) { score += 4 }
        case .moderate:
            score += 6
        case .low, .recovery:
            if heavyAreas.contains(entry.lifeArea) { score -= 20 }
            if lightAreas.contains(entry.lifeArea) { score += 14 }
        }

        // Time-of-day elasticity
        switch context.timeOfDay {
        case .morning:
            if heavyAreas.contains(entry.lifeArea) { score += 6 }
        case .afternoon:
            if context.hour >= 15, heavyAreas.contains(entry.lifeArea) { score -= 12 }
            if lightAreas.contains(entry.lifeArea) { score += 5 }
        case .evening:
            if heavyAreas.contains(entry.lifeArea) { score -= 18 }
            if lightAreas.contains(entry.lifeArea) || entry.lifeArea == .reflection { score += 10 }
        }

        if context.isFridayAfternoon, heavyAreas.contains(entry.lifeArea) {
            score -= 15
        }
        return score
    }

    /// Build a synthetic anchored recovery task for sabotage locks.
    public static func makeRecoveryBlock(
        gapStart: Date,
        gapMinutes: Int,
        day: Date,
        userId: String,
        calendar: Calendar = .current
    ) -> LifeTask {
        let end = gapStart.addingTimeInterval(TimeInterval(gapMinutes * 60))
        var task = LifeTask(
            id: "recovery-\(Int(gapStart.timeIntervalSince1970))",
            title: "Recovery block",
            description: "Protected rest — the Brain locked this after sustained high load.",
            lifeArea: .health,
            priority: .high,
            difficulty: .trivial,
            estimatedMinutes: gapMinutes,
            minimumViableDuration: gapMinutes,
            scheduledDate: calendar.startOfDay(for: day),
            scheduledTime: gapStart,
            tags: ["recovery-block", "brain-locked"],
            schedulingMode: .fixedTime,
            timeConstraint: .anchored,
            scheduledEndTime: end,
            userId: userId
        )
        task.notes = "sabotage_auction"
        return task
    }
}

// MARK: - Resurrected registry (sparkle IDs)

/// Short-lived set of task IDs filled by an auction — UI sparkles these on Today.
public final class ResurrectedTaskRegistry: @unchecked Sendable {
    public static let shared = ResurrectedTaskRegistry()

    private let lock = NSLock()
    private var ids: [String: Date] = [:]
    public var sparkleDuration: TimeInterval = 4 * 3600

    public init() {}

    public func mark(_ taskIDs: [String], now: Date = Date()) {
        lock.lock()
        for id in taskIDs { ids[id] = now }
        lock.unlock()
    }

    public func isResurrected(_ taskID: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let at = ids[taskID] else { return false }
        if now.timeIntervalSince(at) > sparkleDuration {
            ids.removeValue(forKey: taskID)
            return false
        }
        return true
    }

    public func activeIDs(now: Date = Date()) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        ids = ids.filter { now.timeIntervalSince($0.value) <= sparkleDuration }
        return Set(ids.keys)
    }

    public func clear() {
        lock.lock(); ids.removeAll(); lock.unlock()
    }
}
