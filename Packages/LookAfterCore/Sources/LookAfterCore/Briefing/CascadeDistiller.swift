import Foundation

// MARK: - Cascade Distiller

/// Summarizes raw cascade decisions into calm, macro `systemActions` for the AI.
/// Forest, not trees — never dump every 15-minute shift into the Morning Briefing.
public enum CascadeDistiller {

    /// Ignore micro shifts at or below this threshold (minutes).
    public static let significantShiftMinutes = 30

    /// Pure distill from decision log + optional recovery-lock flag.
    public static func distill(
        decisions: [ConflictCascadeDecision],
        triggeredRecoveryLock: Bool = false,
        resurrectedCount: Int = 0
    ) -> [String] {
        var actions: [String] = []
        var parkedCount = 0
        var majorShiftCount = 0
        var floorCompressCount = 0
        var deferCount = 0
        var expiredCount = 0
        var supersededCount = 0

        // Rule 4 — ALWAYS surface sabotage / recovery locks first, untouched in spirit.
        if triggeredRecoveryLock
            || decisions.contains(where: {
                $0.reason.contains("sabotage") && !$0.reason.contains("override")
                    || $0.reason.contains("recovery") && !$0.reason.contains("override")
            }) {
            actions.append("Triggered a Sabotage Auction to enforce a recovery block.")
        }

        for decision in decisions {
            switch decision.action {
            case .keep:
                continue

            case .park:
                parkedCount += 1

            case .shiftLater:
                // Rule 1: ignore known micro shifts under 30 minutes.
                // Unknown shiftMinutes (legacy / unmeasured) counts as a macro action
                // so mutation tallies stay complete when minutes were not recorded.
                if let minutes = decision.shiftMinutes {
                    if minutes > significantShiftMinutes {
                        majorShiftCount += 1
                    }
                } else {
                    majorShiftCount += 1
                }

            case .compress:
                // Rule 2: only mention compress when it hit the viable floor (material).
                if decision.compressHitViableFloor == true {
                    floorCompressCount += 1
                }

            case .deferNextGap:
                deferCount += 1

            case .expired:
                expiredCount += 1

            case .superseded:
                supersededCount += 1
            }
        }

        // Rule 3: group parks into one string.
        if parkedCount == 1 {
            actions.append("Parked 1 flexible task to resolve schedule conflicts.")
        } else if parkedCount > 1 {
            actions.append("Parked \(parkedCount) flexible tasks to resolve schedule conflicts.")
        }

        if majorShiftCount == 1 {
            actions.append("Shifted a major afternoon block to accommodate an overrun.")
        } else if majorShiftCount > 1 {
            actions.append("Shifted \(majorShiftCount) afternoon blocks to accommodate a major overrun.")
        }

        if floorCompressCount == 1 {
            actions.append("Compressed one block down to its viable duration floor.")
        } else if floorCompressCount > 1 {
            actions.append("Compressed \(floorCompressCount) blocks to their viable duration floors.")
        }

        if deferCount == 1 {
            actions.append("Deferred one item into the next open gap.")
        } else if deferCount > 1 {
            actions.append("Deferred \(deferCount) items into later open gaps.")
        }

        if resurrectedCount == 1 {
            actions.append("Filled free time from the waiting room.")
        } else if resurrectedCount > 1 {
            actions.append("Filled free time with \(resurrectedCount) waiting-room items.")
        }

        // Ephemerality — calm acknowledgment of contextual loss (not failure).
        if expiredCount == 1 {
            actions.append(
                "An ephemeral block (meal or timed routine) was skipped when the day got too full; a protected window will be preferred next time."
            )
        } else if expiredCount > 1 {
            actions.append(
                "\(expiredCount) time-bound routines were skipped when the day became over-anchored."
            )
        }

        if supersededCount == 1 {
            actions.append(
                "A missed instance was dropped because the same activity is already scheduled today — no double session."
            )
        } else if supersededCount > 1 {
            actions.append(
                "\(supersededCount) missed instances were dropped to avoid stacking duplicate activities today."
            )
        }

        return actions
    }

    public static func distill(result: ConflictCascadeResult, resurrectedCount: Int = 0) -> [String] {
        distill(
            decisions: result.decisions,
            triggeredRecoveryLock: result.triggeredRecoveryLock,
            resurrectedCount: resurrectedCount
        )
    }

    /// Map distilled strings → mutation facts for the full BriefingPayload path.
    public static func mutationFacts(from actions: [String]) -> [BriefingMutationFact] {
        actions.map { action in
            let code: String
            let lower = action.lowercased()
            if lower.contains("sabotage") || lower.contains("recovery block") {
                code = "sabotage_recovery"
            } else if lower.contains("parked") {
                code = "park"
            } else if lower.contains("shifted") {
                code = "shift_later"
            } else if lower.contains("compressed") {
                code = "compress"
            } else if lower.contains("deferred") {
                code = "defer_gap"
            } else if lower.contains("waiting-room") || lower.contains("waiting room") {
                code = "resurrect"
            } else if lower.contains("skipped") || lower.contains("ephemeral") || lower.contains("time-bound") {
                code = "expired"
            } else if lower.contains("duplicate") || lower.contains("dropped") {
                code = "superseded"
            } else {
                code = "system_action"
            }
            return BriefingMutationFact(code: code, count: extractCount(from: action), reason: action)
        }
    }

    /// Pull leading quantity from distilled copy ("Parked 2 flexible…", "Shifted 3…").
    /// Falls back to 1 when the string uses singular wording ("a", "one", "several").
    private static func extractCount(from action: String) -> Int {
        let tokens = action.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for token in tokens {
            if let n = Int(token), n > 0 { return n }
        }
        let lower = action.lowercased()
        if lower.contains("several") { return 2 }
        return 1
    }
}

// MARK: - Overnight action log (reconcile → briefing wire)

/// Persists distilled macro actions from overnight/background cascade runs.
/// Also retains a rolling multi-day structured history for Weekly Review aggregation.
public final class CascadeActionLog: @unchecked Sendable {
    public static let shared = CascadeActionLog()

    /// Retain structured history for this many calendar days.
    public static let historyRetentionDays = 28

    private let lock = NSLock()
    private var dayKey: String = ""
    private var actions: [String] = []
    /// Rolling structured cascade records (multi-day) feeding `WeeklyReviewAggregator`.
    private var history: [CascadeActionRecord] = []
    private let fileURL: URL?
    private let historyURL: URL?

    public init(directory: URL? = nil) {
        if let directory {
            fileURL = directory.appendingPathComponent("cascade_action_log.json")
            historyURL = directory.appendingPathComponent("cascade_action_history.json")
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            fileURL = support.appendingPathComponent("cascade_action_log.json")
            historyURL = support.appendingPathComponent("cascade_action_history.json")
        } else {
            fileURL = nil
            historyURL = nil
        }
        load()
        loadHistory()
    }

    public static func inMemory() -> CascadeActionLog {
        CascadeActionLog(memory: true)
    }

    private init(memory: Bool) {
        fileURL = nil
        historyURL = nil
        dayKey = ""
        actions = []
        history = []
    }

    /// Record a cascade result — distills first, merges into today's log,
    /// and appends structured records into multi-day history.
    public func record(
        result: ConflictCascadeResult,
        resurrectedCount: Int = 0,
        recoveryDurationMinutes: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let key = TelemetryLogRotation.dayKey(for: now, calendar: calendar)
        let distilled = CascadeDistiller.distill(result: result, resurrectedCount: resurrectedCount)
        let records = CascadeActionRecordBuilder.records(
            from: result.decisions,
            triggeredRecoveryLock: result.triggeredRecoveryLock,
            recoveryDurationMinutes: recoveryDurationMinutes,
            now: now
        )

        lock.lock()
        if dayKey != key {
            dayKey = key
            actions = []
        }
        for action in distilled where !actions.contains(action) {
            actions.append(action)
        }
        if !records.isEmpty {
            history.append(contentsOf: records)
            pruneHistoryLocked(now: now, calendar: calendar)
        }
        let snapshot = actions
        let snapKey = dayKey
        let historySnap = history
        lock.unlock()

        if !distilled.isEmpty {
            persist(dayKey: snapKey, actions: snapshot)
        }
        if !records.isEmpty {
            persistHistory(historySnap)
        }
    }

    /// Append pre-built structured records (tests / backfill).
    public func appendHistory(_ records: [CascadeActionRecord], now: Date = Date(), calendar: Calendar = .current) {
        guard !records.isEmpty else { return }
        lock.lock()
        history.append(contentsOf: records)
        pruneHistoryLocked(now: now, calendar: calendar)
        let snap = history
        lock.unlock()
        persistHistory(snap)
    }

    /// Macro system actions for today's briefing (empty if none).
    public func systemActions(for now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let key = TelemetryLogRotation.dayKey(for: now, calendar: calendar)
        lock.lock(); defer { lock.unlock() }
        guard dayKey == key else { return [] }
        return actions
    }

    /// Full structured history retained for weekly review (thread-safe copy).
    public func historyRecords() -> [CascadeActionRecord] {
        lock.lock(); defer { lock.unlock() }
        return history
    }

    /// Structured history filtered to the 7-day window ending at `weekEnding`.
    public func historyRecords(
        weekEnding: Date,
        calendar: Calendar = .current
    ) -> [CascadeActionRecord] {
        let bounds = WeeklyReviewAggregator.weekBounds(ending: weekEnding, calendar: calendar)
        lock.lock(); defer { lock.unlock() }
        return history.filter { $0.timestamp >= bounds.start && $0.timestamp < bounds.endExclusive }
    }

    public func clear() {
        lock.lock()
        dayKey = ""
        actions = []
        history = []
        lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        if let historyURL { try? FileManager.default.removeItem(at: historyURL) }
    }

    private func pruneHistoryLocked(now: Date, calendar: Calendar) {
        let endDay = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.historyRetentionDays, to: endDay) else { return }
        history.removeAll { $0.timestamp < cutoff }
    }

    private func persist(dayKey: String, actions: [String]) {
        guard let fileURL else { return }
        let envelope = ["dayKey": dayKey, "actions": actions] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func persistHistory(_ records: [CascadeActionRecord]) {
        guard let historyURL else { return }
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: historyURL, options: [.atomic])
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = obj["dayKey"] as? String,
              let list = obj["actions"] as? [String] else { return }
        dayKey = key
        actions = list
    }

    private func loadHistory() {
        guard let historyURL,
              let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([CascadeActionRecord].self, from: data) else { return }
        history = decoded
    }
}
