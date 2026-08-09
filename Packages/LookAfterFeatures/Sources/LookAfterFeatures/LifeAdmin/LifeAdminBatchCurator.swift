import Foundation
import LookAfterCore

public struct LifeAdminBatchItem: Identifiable, Sendable, Equatable {
    public enum ItemKind: String, Sendable, Codable {
        case bill
        case shopping
        case medication
        case contact
    }

    public var id: String
    public var kind: ItemKind
    public var title: String
    public var estimatedMinutes: Int
    public var entityID: String

    public init(id: String = UUID().uuidString, kind: ItemKind, title: String, estimatedMinutes: Int, entityID: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.entityID = entityID
    }
}

public struct LifeAdminBatch: Sendable, Equatable {
    public var items: [LifeAdminBatchItem]
    public var totalMinutes: Int
    public var narrative: String
    public var suggestedWindowLabel: String

    public init(items: [LifeAdminBatchItem], totalMinutes: Int, narrative: String, suggestedWindowLabel: String = "This afternoon") {
        self.items = items
        self.totalMinutes = totalMinutes
        self.narrative = narrative
        self.suggestedWindowLabel = suggestedWindowLabel
    }
}

/// Curates a 15-minute life-admin block from silent module data.
public enum LifeAdminBatchCurator {
    public struct Input: Sendable {
        public var bills: [BillItem]
        public var shoppingItems: [ShoppingItem]
        public var medications: [Medication]
        public var contacts: [RelationshipContact]
        public var now: Date

        public init(
            bills: [BillItem],
            shoppingItems: [ShoppingItem],
            medications: [Medication],
            contacts: [RelationshipContact],
            now: Date = Date()
        ) {
            self.bills = bills
            self.shoppingItems = shoppingItems
            self.medications = medications
            self.contacts = contacts
            self.now = now
        }
    }

    public static func curate(_ input: Input, budgetMinutes: Int = 20) -> LifeAdminBatch? {
        var items: [LifeAdminBatchItem] = []
        var remaining = budgetMinutes

        for bill in input.bills.filter({ !$0.isPaid }).sorted(by: { $0.dueDate < $1.dueDate }).prefix(2) {
            let minutes = 5
            guard remaining >= minutes else { break }
            items.append(LifeAdminBatchItem(kind: .bill, title: "Pay \(bill.title)", estimatedMinutes: minutes, entityID: bill.id))
            remaining -= minutes
        }

        for med in input.medications.filter({ !$0.isTaken }).prefix(1) {
            let minutes = 2
            guard remaining >= minutes else { break }
            items.append(LifeAdminBatchItem(kind: .medication, title: "Take \(med.name)", estimatedMinutes: minutes, entityID: med.id))
            remaining -= minutes
        }

        for item in input.shoppingItems.filter({ !$0.isPurchased && $0.isEssential }).prefix(2) {
            let minutes = 3
            guard remaining >= minutes else { break }
            items.append(LifeAdminBatchItem(kind: .shopping, title: "Buy \(item.name)", estimatedMinutes: minutes, entityID: item.id))
            remaining -= minutes
        }

        for contact in input.contacts.filter(\.needsContact).prefix(1) {
            let minutes = 5
            guard remaining >= minutes else { break }
            items.append(LifeAdminBatchItem(kind: .contact, title: "Check in with \(contact.name)", estimatedMinutes: minutes, entityID: contact.id))
            remaining -= minutes
        }

        guard !items.isEmpty else { return nil }
        let total = items.map(\.estimatedMinutes).reduce(0, +)
        let narrative = "You have \(items.count) life-admin item\(items.count == 1 ? "" : "s") (~\(total) min) waiting quietly."
        return LifeAdminBatch(items: items, totalMinutes: total, narrative: narrative)
    }

    public static func proactiveAction(from batch: LifeAdminBatch) -> ProactiveAction {
        ProactiveAction(
            id: "life-admin-batch",
            kind: .lifeAdminBatch,
            severity: .medium,
            message: batch.narrative,
            options: ["Start \(batch.totalMinutes)-min block", "Schedule for Friday", "Dismiss"],
            surface: .banner,
            metadata: ["totalMinutes": "\(batch.totalMinutes)"]
        )
    }
}
