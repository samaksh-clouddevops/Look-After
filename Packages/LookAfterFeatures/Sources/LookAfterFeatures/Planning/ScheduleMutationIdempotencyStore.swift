import Foundation

/// Session-scoped idempotency for AI plan mutations (Wave 2 / B5).
@MainActor
public final class ScheduleMutationIdempotencyStore {
    public static let shared = ScheduleMutationIdempotencyStore()

    private var applied = Set<String>()
    private let maxEntries = 200

    private init() {}

    public func wasApplied(_ fingerprint: String) -> Bool {
        applied.contains(fingerprint)
    }

    public func markApplied(_ fingerprint: String) {
        if applied.count >= maxEntries {
            applied.removeAll(keepingCapacity: true)
        }
        applied.insert(fingerprint)
    }

    public func reset() {
        applied.removeAll()
    }

    public static func fingerprint(_ mutation: PlanMutation) -> String {
        let parts: [String] = [
            mutation.kind.rawValue,
            mutation.taskID ?? "",
            mutation.title ?? "",
            mutation.startHour.map(String.init) ?? "",
            mutation.startMinute.map(String.init) ?? "",
            mutation.deferToTomorrow ? "1" : "0",
            mutation.shoppingItemName ?? "",
            mutation.medicationID ?? "",
            mutation.dayCount.map(String.init) ?? ""
        ]
        return parts.joined(separator: "|")
    }
}
