import Foundation

/// Deterministic cross-domain fusion rules (bills, sleep, meds, capacity).
public enum CrossDomainFusionAnalyzer {
    public struct Input: Sendable {
        public var actions: [ProactiveAction]
        public var bills: [BillItem]
        public var capacityBand: ExecutiveCapacityBand?
        public var sleepHours: Double?
        public var medications: [Medication]
        public var now: Date
        public var calendar: Calendar

        public init(
            actions: [ProactiveAction],
            bills: [BillItem] = [],
            capacityBand: ExecutiveCapacityBand? = nil,
            sleepHours: Double? = nil,
            medications: [Medication] = [],
            now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.actions = actions
            self.bills = bills
            self.capacityBand = capacityBand
            self.sleepHours = sleepHours
            self.medications = medications
            self.now = now
            self.calendar = calendar
        }
    }

    public static func fuse(_ input: Input) -> [ProactiveAction] {
        var actions = input.actions
        let overdueBills = input.bills.filter { !$0.isPaid && $0.dueDate < input.now }
        let missedMeds = input.medications.filter { !$0.isTaken }
        let isFriday = input.calendar.component(.weekday, from: input.now) == 6
        let badSleep = (input.sleepHours ?? 8) < 6

        if input.capacityBand == .recoveryMode, !overdueBills.isEmpty {
            actions = boostLifeAdminBatch(actions, reason: "Recovery day + overdue bills")
        }

        if badSleep, !missedMeds.isEmpty {
            if let index = actions.firstIndex(where: { $0.kind == .badDay }) {
                var boosted = actions[index]
                boosted = ProactiveAction(
                    id: boosted.id,
                    kind: boosted.kind,
                    severity: .high,
                    message: "Rough sleep and missed meds — \(boosted.message)",
                    options: boosted.options,
                    surface: boosted.surface,
                    relatedTaskIDs: boosted.relatedTaskIDs,
                    relatedInboxIDs: boosted.relatedInboxIDs,
                    expiresAt: boosted.expiresAt,
                    metadata: boosted.metadata.merging(["fusion": "medSleep"]) { $1 }
                )
                actions[index] = boosted
            } else {
                actions.insert(BadDayDetector.proactiveAction(from: BadDaySignal(
                    score: 4,
                    reasons: ["Missed meds + short sleep"],
                    recommendedTemplate: .minimumViable
                )), at: 0)
            }
        }

        if isFriday, !overdueBills.isEmpty {
            actions = boostLifeAdminBatch(actions, reason: "Friday bill sweep")
        }

        return actions
    }

    private static func boostLifeAdminBatch(_ actions: [ProactiveAction], reason: String) -> [ProactiveAction] {
        guard let index = actions.firstIndex(where: { $0.kind == .lifeAdminBatch }) else { return actions }
        var copy = actions
        var action = copy[index]
        action = ProactiveAction(
            id: action.id,
            kind: action.kind,
            severity: .high,
            message: action.message,
            options: action.options,
            surface: action.surface,
            relatedTaskIDs: action.relatedTaskIDs,
            relatedInboxIDs: action.relatedInboxIDs,
            expiresAt: action.expiresAt,
            metadata: action.metadata.merging(["fusion": reason]) { $1 }
        )
        copy[index] = action
        return copy
    }
}
