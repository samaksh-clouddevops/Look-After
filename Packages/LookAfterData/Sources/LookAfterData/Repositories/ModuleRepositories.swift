import Foundation
import FirebaseFirestore
import LookAfterCore

// MARK: - Shared module helpers

@MainActor
enum ModuleLocalStore {
    static let sqlite = ModuleEntitySQLiteStore.shared

    static func loadMoneyPlan() -> MoneyPlan? {
        (try? sqlite.loadAll(MoneyPlan.self, collection: .moneyPlan))?.first
    }

    static func saveMoneyPlan(_ plan: MoneyPlan?) {
        if let plan {
            try? sqlite.replaceAll([plan], collection: .moneyPlan, id: { $0.id })
        } else {
            try? sqlite.replaceAll([MoneyPlan](), collection: .moneyPlan, id: { $0.id })
        }
    }

    static func loadDailyExpenses() -> [DailyExpense] {
        (try? sqlite.loadAll(DailyExpense.self, collection: .dailyExpenses)) ?? []
    }

    static func saveDailyExpenses(_ items: [DailyExpense]) {
        try? sqlite.replaceAll(items, collection: .dailyExpenses, id: { $0.id })
    }

    static func loadSpendKindMemory() -> [SpendKindMemory] {
        (try? sqlite.loadAll(SpendKindMemory.self, collection: .spendKindMemory)) ?? []
    }

    static func saveSpendKindMemory(_ items: [SpendKindMemory]) {
        try? sqlite.replaceAll(items, collection: .spendKindMemory, id: { $0.noteKey })
    }

    static func loadBills() -> [BillItem] {
        (try? sqlite.loadAll(BillItem.self, collection: .bills)) ?? []
    }

    static func saveBills(_ items: [BillItem]) {
        try? sqlite.replaceAll(items, collection: .bills, id: { $0.id })
    }

    static func loadShopping() -> [ShoppingItem] {
        (try? sqlite.loadAll(ShoppingItem.self, collection: .shoppingItems)) ?? []
    }

    static func saveShopping(_ items: [ShoppingItem]) {
        try? sqlite.replaceAll(items, collection: .shoppingItems, id: { $0.id })
    }

    static func loadRelationships() -> [RelationshipContact] {
        (try? sqlite.loadAll(RelationshipContact.self, collection: .relationships)) ?? []
    }

    static func saveRelationships(_ items: [RelationshipContact]) {
        try? sqlite.replaceAll(items, collection: .relationships, id: { $0.id })
    }

    static func loadJournal() -> [JournalEntry] {
        (try? sqlite.loadAll(JournalEntry.self, collection: .journalEntries)) ?? []
    }

    static func saveJournal(_ items: [JournalEntry]) {
        try? sqlite.replaceAll(items, collection: .journalEntries, id: { $0.id })
    }

    static func loadHydration() -> [HydrationLog] {
        (try? sqlite.loadAll(HydrationLog.self, collection: .hydrationLogs)) ?? []
    }

    static func saveHydration(_ items: [HydrationLog]) {
        try? sqlite.replaceAll(items, collection: .hydrationLogs, id: { $0.id })
    }

    static func enqueueUpsert<T: Encodable>(_ item: T, collection: String, id: String, userId: String, merge: Bool) {
        CloudSyncOutbox.shared.enqueueCodable(
            item,
            collection: collection,
            documentId: id,
            userId: userId,
            merge: merge
        )
    }

    static func enqueueDelete(collection: String, id: String, userId: String) {
        CloudSyncOutbox.shared.enqueue(
            collection: collection,
            documentId: id,
            userId: userId,
            operation: .delete,
            payloadJSON: nil
        )
    }
}

// MARK: - Finance & Bills Repository

@MainActor
public final class BillRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "bills"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    public func getAll(for userId: String) async throws -> [BillItem] {
        let local = ModuleLocalStore.loadBills()
        guard let ref = firebase.userCollection(collection) else {
            return local.sorted { $0.dueDate < $1.dueDate }
        }
        do {
            let snapshot = try await ref.order(by: "dueDate", descending: false).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(BillItem.self, from: $0) }
            let merged = ModuleEntityMerge.merge(local: local, remote: remote, id: \.id)
            ModuleLocalStore.saveBills(merged)
            return merged.sorted { $0.dueDate < $1.dueDate }
        } catch {
            return local.sorted { $0.dueDate < $1.dueDate }
        }
    }

    public func create(_ item: BillItem) async throws {
        var mutable = item
        mutable.userId = firebase.currentUserId ?? mutable.userId
        var items = ModuleLocalStore.loadBills()
        items.append(mutable)
        ModuleLocalStore.saveBills(items)
        ModuleLocalStore.enqueueUpsert(mutable, collection: collection, id: mutable.id, userId: mutable.userId, merge: false)
    }

    public func save(_ item: BillItem) async throws {
        var mutable = item
        mutable.userId = firebase.currentUserId ?? mutable.userId
        var items = ModuleLocalStore.loadBills()
        if let index = items.firstIndex(where: { $0.id == mutable.id }) {
            items[index] = mutable
        } else {
            items.append(mutable)
        }
        ModuleLocalStore.saveBills(items)
        ModuleLocalStore.enqueueUpsert(mutable, collection: collection, id: mutable.id, userId: mutable.userId, merge: true)
    }

    public func togglePaid(_ item: BillItem) async throws {
        var items = ModuleLocalStore.loadBills()
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isPaid.toggle()
        items[idx].paidAt = items[idx].isPaid ? Date() : nil
        let updated = items[idx]
        ModuleLocalStore.saveBills(items)
        ModuleLocalStore.enqueueUpsert(updated, collection: collection, id: updated.id, userId: updated.userId, merge: true)
    }

    public func delete(_ item: BillItem) async throws {
        var items = ModuleLocalStore.loadBills()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveBills(items)
        ModuleLocalStore.enqueueDelete(collection: collection, id: item.id, userId: item.userId)
    }
}

// MARK: - Money planner

@MainActor
public final class MoneyRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let planCollection = "moneyPlan"
    private let expenseCollection = "dailyExpenses"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    public func loadPlan(for userId: String) async throws -> MoneyPlan? {
        let local = ModuleLocalStore.loadMoneyPlan()
        guard let ref = firebase.userCollection(planCollection) else { return local }
        do {
            let snapshot = try await ref.getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(MoneyPlan.self, from: $0) }
            let merged = remote.first ?? local
            if let merged { ModuleLocalStore.saveMoneyPlan(merged) }
            return merged
        } catch {
            return local
        }
    }

    public func savePlan(_ plan: MoneyPlan) async throws {
        var mutable = plan
        mutable.userId = firebase.currentUserId ?? mutable.userId
        if mutable.id.isEmpty { mutable.id = mutable.userId }
        ModuleLocalStore.saveMoneyPlan(mutable)
        ModuleLocalStore.enqueueUpsert(mutable, collection: planCollection, id: mutable.id, userId: mutable.userId, merge: true)
    }

    public func loadExpenses(for userId: String) async throws -> [DailyExpense] {
        let local = ModuleLocalStore.loadDailyExpenses()
        guard let ref = firebase.userCollection(expenseCollection) else { return local }
        do {
            let snapshot = try await ref.getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(DailyExpense.self, from: $0) }
            let merged = ModuleEntityMerge.merge(local: local, remote: remote, id: \.id)
            ModuleLocalStore.saveDailyExpenses(merged)
            return merged
        } catch {
            return local
        }
    }

    public func saveExpense(_ item: DailyExpense) async throws {
        var mutable = item
        mutable.userId = firebase.currentUserId ?? mutable.userId
        var items = ModuleLocalStore.loadDailyExpenses()
        items.removeAll { $0.id == mutable.id }
        items.append(mutable)
        ModuleLocalStore.saveDailyExpenses(items)
        ModuleLocalStore.enqueueUpsert(mutable, collection: expenseCollection, id: mutable.id, userId: mutable.userId, merge: true)
    }

    public func loadSpendKindMemory() -> [SpendKindMemory] {
        ModuleLocalStore.loadSpendKindMemory()
    }

    public func saveSpendKindMemory(_ items: [SpendKindMemory]) {
        ModuleLocalStore.saveSpendKindMemory(items)
    }

    public func deleteExpense(_ item: DailyExpense) async throws {
        var items = ModuleLocalStore.loadDailyExpenses()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveDailyExpenses(items)
        ModuleLocalStore.enqueueDelete(collection: expenseCollection, id: item.id, userId: item.userId)
    }
}

// MARK: - Shopping & Inventory Repository

@MainActor
public final class ShoppingRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "shopping_items"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    public func getAll(for userId: String) async throws -> [ShoppingItem] {
        let localItems = ModuleLocalStore.loadShopping()
        guard let ref = firebase.userCollection(collection) else {
            return localItems.sorted { $0.addedAt > $1.addedAt }
        }
        do {
            let snapshot = try await ref.order(by: "addedAt", descending: true).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(ShoppingItem.self, from: $0) }
            let merged = ModuleEntityMerge.merge(local: localItems, remote: remote, id: \.id)
            ModuleLocalStore.saveShopping(merged)
            return merged.sorted { $0.addedAt > $1.addedAt }
        } catch {
            print("[ShoppingList] Remote load failed, using local cache: \(error.localizedDescription)")
            return localItems.sorted { $0.addedAt > $1.addedAt }
        }
    }

    public func create(_ item: ShoppingItem) async throws {
        var mutable = item
        mutable.userId = firebase.currentUserId ?? mutable.userId
        var items = ModuleLocalStore.loadShopping()
        if !items.contains(where: { $0.id == mutable.id }) {
            items.append(mutable)
            ModuleLocalStore.saveShopping(items)
        }
        ModuleLocalStore.enqueueUpsert(mutable, collection: collection, id: mutable.id, userId: mutable.userId, merge: false)
    }

    public func togglePurchased(_ item: ShoppingItem) async throws {
        var items = ModuleLocalStore.loadShopping()
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isPurchased.toggle()
        items[idx].purchasedAt = items[idx].isPurchased ? Date() : nil
        let updated = items[idx]
        ModuleLocalStore.saveShopping(items)
        ModuleLocalStore.enqueueUpsert(updated, collection: collection, id: updated.id, userId: updated.userId, merge: true)
    }

    public func delete(_ item: ShoppingItem) async throws {
        var items = ModuleLocalStore.loadShopping()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveShopping(items)
        ModuleLocalStore.enqueueDelete(collection: collection, id: item.id, userId: item.userId)
    }
}

// MARK: - Relationships Repository

@MainActor
public final class RelationshipRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "relationships"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    public func getAll(for userId: String) async throws -> [RelationshipContact] {
        let local = ModuleLocalStore.loadRelationships()
        guard let ref = firebase.userCollection(collection) else {
            return local
        }
        do {
            let snapshot = try await ref.getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(RelationshipContact.self, from: $0) }
            let merged = ModuleEntityMerge.merge(local: local, remote: remote, id: \.id)
            ModuleLocalStore.saveRelationships(merged)
            return merged
        } catch {
            return local
        }
    }

    public func create(_ item: RelationshipContact) async throws {
        var mutable = item
        mutable.userId = firebase.currentUserId ?? mutable.userId
        var items = ModuleLocalStore.loadRelationships()
        items.append(mutable)
        ModuleLocalStore.saveRelationships(items)
        ModuleLocalStore.enqueueUpsert(mutable, collection: collection, id: mutable.id, userId: mutable.userId, merge: false)
    }

    public func logContact(_ contact: RelationshipContact) async throws {
        var items = ModuleLocalStore.loadRelationships()
        guard let idx = items.firstIndex(where: { $0.id == contact.id }) else { return }
        items[idx].lastContactedAt = Date()
        let updated = items[idx]
        ModuleLocalStore.saveRelationships(items)
        ModuleLocalStore.enqueueUpsert(updated, collection: collection, id: updated.id, userId: updated.userId, merge: true)
    }

    public func delete(_ contact: RelationshipContact) async throws {
        var items = ModuleLocalStore.loadRelationships()
        items.removeAll { $0.id == contact.id }
        ModuleLocalStore.saveRelationships(items)
        ModuleLocalStore.enqueueDelete(collection: collection, id: contact.id, userId: contact.userId)
    }
}

// MARK: - Journaling Repository

@MainActor
public final class JournalRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "journal_entries"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    public func getAll(for userId: String) async throws -> [JournalEntry] {
        let local = ModuleLocalStore.loadJournal()
        guard let ref = firebase.userCollection(collection) else {
            return local.sorted { $0.createdAt > $1.createdAt }
        }
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(JournalEntry.self, from: $0) }
            let merged = ModuleEntityMerge.merge(local: local, remote: remote, id: \.id)
            ModuleLocalStore.saveJournal(merged)
            return merged.sorted { $0.createdAt > $1.createdAt }
        } catch {
            return local.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func create(_ item: JournalEntry) async throws {
        var mutable = item
        mutable.userId = firebase.currentUserId ?? mutable.userId
        var items = ModuleLocalStore.loadJournal()
        items.insert(mutable, at: 0)
        ModuleLocalStore.saveJournal(items)
        ModuleLocalStore.enqueueUpsert(mutable, collection: collection, id: mutable.id, userId: mutable.userId, merge: false)
    }

    public func delete(_ item: JournalEntry) async throws {
        var items = ModuleLocalStore.loadJournal()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveJournal(items)
        ModuleLocalStore.enqueueDelete(collection: collection, id: item.id, userId: item.userId)
    }
}

// MARK: - Hydration Repository

@MainActor
public final class HydrationRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "hydration_logs"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    /// Returns only today's logs — hydration is a daily-reset metric, not a running history.
    public func getToday(for userId: String) async throws -> [HydrationLog] {
        let local = ModuleLocalStore.loadHydration().filter { Calendar.current.isDateInToday($0.loggedAt) }
        guard let ref = firebase.userCollection(collection) else {
            return local.sorted { $0.loggedAt < $1.loggedAt }
        }
        do {
            let snapshot = try await ref.order(by: "loggedAt", descending: true).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(HydrationLog.self, from: $0) }
            let remoteToday = remote.filter { Calendar.current.isDateInToday($0.loggedAt) }
            let merged = ModuleEntityMerge.merge(local: local, remote: remoteToday, id: \.id)
            // Preserve any older (non-today) logs already on disk instead of pruning them here —
            // stale-day cleanup is a separate concern from this read path.
            let stale = ModuleLocalStore.loadHydration().filter { !Calendar.current.isDateInToday($0.loggedAt) }
            ModuleLocalStore.saveHydration(stale + merged)
            return merged.sorted { $0.loggedAt < $1.loggedAt }
        } catch {
            return local.sorted { $0.loggedAt < $1.loggedAt }
        }
    }

    public func create(_ item: HydrationLog) async throws {
        var mutable = item
        mutable.userId = firebase.currentUserId ?? mutable.userId
        var items = ModuleLocalStore.loadHydration()
        items.append(mutable)
        ModuleLocalStore.saveHydration(items)
        ModuleLocalStore.enqueueUpsert(mutable, collection: collection, id: mutable.id, userId: mutable.userId, merge: false)
    }

    public func delete(_ item: HydrationLog) async throws {
        var items = ModuleLocalStore.loadHydration()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveHydration(items)
        ModuleLocalStore.enqueueDelete(collection: collection, id: item.id, userId: item.userId)
    }
}

/// Union-by-id merge for module entities (local fills gaps remote missed).
enum ModuleEntityMerge {
    static func merge<T>(local: [T], remote: [T], id: (T) -> String) -> [T] {
        var byID = Dictionary(uniqueKeysWithValues: remote.map { (id($0), $0) })
        for item in local where byID[id(item)] == nil {
            byID[id(item)] = item
        }
        return Array(byID.values)
    }
}
