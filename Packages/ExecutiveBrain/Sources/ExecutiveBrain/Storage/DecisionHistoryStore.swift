import Foundation
import LookAfterCore

/// Append-only decision history for policy learning and Brain Inspector.
public final class DecisionHistoryStore: @unchecked Sendable {
    public static let shared = DecisionHistoryStore()

    private let lock = NSLock()
    private var records: [DecisionRecord] = []
    private let maxRecords = 200
    private let storageKey = "executiveBrain.decisionHistory"

    public init(loadPersisted: Bool = true) {
        if loadPersisted { load() }
    }

    public func allRecords() -> [DecisionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    public func recent(limit: Int = 20) -> [DecisionRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records.suffix(limit).reversed())
    }

    @discardableResult
    public func recordIssued(
        intent: ExecutiveIntent,
        reasoning: ReasoningTrace,
        simulations: [PlanSimulation]
    ) -> DecisionRecord {
        let summary = reasoning.conclusions.prefix(2).joined(separator: " ")
        let record = DecisionRecord(
            intent: intent,
            reasoningSummary: summary.isEmpty ? intent.intention : summary,
            factorCount: reasoning.factors.count,
            simulations: simulations
        )

        lock.lock()
        records.append(record)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        lock.unlock()

        persist()
        return record
    }

    public func recordAccepted(recordID: String) {
        updateRecord(recordID: recordID) { $0.disposition = .accepted }
    }

    public func recordIgnored(recordID: String, reason: String?) {
        updateRecord(recordID: recordID) { record in
            record.disposition = .ignored
            record.result = DecisionResult(ignoreReason: reason)
            record.lesson = inferLesson(from: record, ignored: true, reason: reason)
        }
    }

    public func recordCompleted(recordID: String, actualMinutes: Int) {
        updateRecord(recordID: recordID) { record in
            record.disposition = .completed
            record.result = DecisionResult(actualMinutes: actualMinutes, completed: true)
            let estimated = record.intent.semantics.estimateMinutes
            if actualMinutes <= estimated + 5 {
                record.lesson = PolicyLesson(
                    pattern: record.intent.intervention,
                    policy: "Confidence increased — finished near estimate",
                    confidenceAdjustment: 0.05
                )
            }
        }
    }

    // MARK: - Private

    private func updateRecord(recordID: String, mutate: (inout DecisionRecord) -> Void) {
        lock.lock()
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            mutate(&records[index])
        }
        lock.unlock()
        persist()
    }

    private func inferLesson(from record: DecisionRecord, ignored: Bool, reason: String?) -> PolicyLesson? {
        guard ignored, let reason, !reason.isEmpty else { return nil }
        return PolicyLesson(
            pattern: record.intent.intervention,
            policy: "Don't recommend immediately after: \(reason)",
            confidenceAdjustment: -0.08
        )
    }

    private func persist() {
        lock.lock()
        let snapshot = records
        lock.unlock()

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DecisionRecord].self, from: data) else {
            return
        }
        lock.lock()
        records = decoded
        lock.unlock()
    }

    /// Wipes persisted decision history (developer reset).
    public func clearAll() {
        lock.lock()
        records = []
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
