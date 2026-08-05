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
                // Rule 1: ignore shifts under 30 minutes.
                let minutes = decision.shiftMinutes ?? 0
                if minutes > significantShiftMinutes {
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
            actions.append("Shifted several afternoon blocks to accommodate a major overrun.")
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
            return BriefingMutationFact(code: code, count: 1, reason: action)
        }
    }
}

// MARK: - Overnight action log (reconcile → briefing wire)

/// Persists distilled macro actions from overnight/background cascade runs.
public final class CascadeActionLog: @unchecked Sendable {
    public static let shared = CascadeActionLog()

    private let lock = NSLock()
    private var dayKey: String = ""
    private var actions: [String] = []
    private let fileURL: URL?

    public init(directory: URL? = nil) {
        if let directory {
            fileURL = directory.appendingPathComponent("cascade_action_log.json")
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            fileURL = support.appendingPathComponent("cascade_action_log.json")
        } else {
            fileURL = nil
        }
        load()
    }

    public static func inMemory() -> CascadeActionLog {
        CascadeActionLog(memory: true)
    }

    private init(memory: Bool) {
        fileURL = nil
        dayKey = ""
        actions = []
    }

    /// Record a cascade result — distills first, merges into today's log.
    public func record(
        result: ConflictCascadeResult,
        resurrectedCount: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let key = TelemetryLogRotation.dayKey(for: now, calendar: calendar)
        let distilled = CascadeDistiller.distill(result: result, resurrectedCount: resurrectedCount)
        guard !distilled.isEmpty else { return }
        lock.lock()
        if dayKey != key {
            dayKey = key
            actions = []
        }
        for action in distilled where !actions.contains(action) {
            actions.append(action)
        }
        let snapshot = actions
        let snapKey = dayKey
        lock.unlock()
        persist(dayKey: snapKey, actions: snapshot)
    }

    /// Macro system actions for today's briefing (empty if none).
    public func systemActions(for now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let key = TelemetryLogRotation.dayKey(for: now, calendar: calendar)
        lock.lock(); defer { lock.unlock() }
        guard dayKey == key else { return [] }
        return actions
    }

    public func clear() {
        lock.lock()
        dayKey = ""
        actions = []
        lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func persist(dayKey: String, actions: [String]) {
        guard let fileURL else { return }
        let envelope = ["dayKey": dayKey, "actions": actions] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        try? data.write(to: fileURL, options: [.atomic])
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
}
