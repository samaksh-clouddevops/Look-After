import Foundation
import FirebaseFirestore
import LookAfterCore

// MARK: - Shared module helpers

@MainActor
private enum ModuleLocalStore {
    static let sqlite = ModuleEntitySQLiteStore.shared

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
