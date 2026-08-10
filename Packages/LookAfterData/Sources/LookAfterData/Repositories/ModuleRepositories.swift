import Foundation
import FirebaseFirestore
import LookAfterCore

// MARK: - Local dual-write helper (JSON + SQLite)

@MainActor
enum ModuleLocalStore {
    static func loadBills() -> [BillItem] {
        let sql = JSONEntitySQLiteStore.sharedBills
        sql.migrateFromJSONIfNeeded(
            as: BillItem.self,
            filename: "bills",
            id: \.id,
            userId: \.userId
        )
        let rows = (try? sql.loadAll(as: BillItem.self)) ?? []
        if !rows.isEmpty { return rows }
        return LocalPersistenceManager.shared.load([BillItem].self, filename: "bills")
    }

    static func saveBills(_ items: [BillItem]) {
        LocalPersistenceManager.shared.save(items, filename: "bills")
        let sql = JSONEntitySQLiteStore.sharedBills
        try? sql.replaceAll(userId: "", items: items.map { ($0.id, $0) })
    }

    static func loadShopping() -> [ShoppingItem] {
        let sql = JSONEntitySQLiteStore.sharedShopping
        sql.migrateFromJSONIfNeeded(
            as: ShoppingItem.self,
            filename: "shopping_items",
            id: \.id,
            userId: \.userId
        )
        let rows = (try? sql.loadAll(as: ShoppingItem.self)) ?? []
        if !rows.isEmpty { return rows }
        return LocalPersistenceManager.shared.load([ShoppingItem].self, filename: "shopping_items")
    }

    static func saveShopping(_ items: [ShoppingItem]) {
        LocalPersistenceManager.shared.save(items, filename: "shopping_items")
        try? JSONEntitySQLiteStore.sharedShopping.replaceAll(
            userId: "",
            items: items.map { ($0.id, $0) }
        )
    }

    static func loadRelationships() -> [RelationshipContact] {
        let sql = JSONEntitySQLiteStore.sharedRelationships
        sql.migrateFromJSONIfNeeded(
            as: RelationshipContact.self,
            filename: "relationships",
            id: \.id,
            userId: \.userId
        )
        let rows = (try? sql.loadAll(as: RelationshipContact.self)) ?? []
        if !rows.isEmpty { return rows }
        return LocalPersistenceManager.shared.load([RelationshipContact].self, filename: "relationships")
    }

    static func saveRelationships(_ items: [RelationshipContact]) {
        LocalPersistenceManager.shared.save(items, filename: "relationships")
        try? JSONEntitySQLiteStore.sharedRelationships.replaceAll(
            userId: "",
            items: items.map { ($0.id, $0) }
        )
    }

    static func loadJournal() -> [JournalEntry] {
        let sql = JSONEntitySQLiteStore.sharedJournal
        sql.migrateFromJSONIfNeeded(
            as: JournalEntry.self,
            filename: "journal_entries",
            id: \.id,
            userId: \.userId
        )
        let rows = (try? sql.loadAll(as: JournalEntry.self)) ?? []
        if !rows.isEmpty { return rows }
        return LocalPersistenceManager.shared.load([JournalEntry].self, filename: "journal_entries")
    }

    static func saveJournal(_ items: [JournalEntry]) {
        LocalPersistenceManager.shared.save(items, filename: "journal_entries")
        try? JSONEntitySQLiteStore.sharedJournal.replaceAll(
            userId: "",
            items: items.map { ($0.id, $0) }
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
        let localItems = ModuleLocalStore.loadBills()
        guard let ref = firebase.userCollection(collection) else {
            return localItems
        }
        do {
            let snapshot = try await ref.order(by: "dueDate", descending: false).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(BillItem.self, from: $0) }
            if !remote.isEmpty {
                ModuleLocalStore.saveBills(remote)
                return remote
            }
            return localItems
        } catch {
            return localItems
        }
    }

    public func create(_ item: BillItem) async throws {
        var items = ModuleLocalStore.loadBills()
        items.append(item)
        ModuleLocalStore.saveBills(items)

        guard let ref = firebase.userCollection(collection) else { return }
        var mutable = item; mutable.userId = firebase.currentUserId ?? ""
        let data = try SharedFormatters.jsonEncoderSeconds.encode(mutable)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict)
    }

    public func togglePaid(_ item: BillItem) async throws {
        var items = ModuleLocalStore.loadBills()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPaid.toggle()
            items[idx].paidAt = items[idx].isPaid ? Date() : nil
            ModuleLocalStore.saveBills(items)
        }

        guard let ref = firebase.userCollection(collection) else { return }
        var updated = item
        updated.isPaid.toggle()
        updated.paidAt = updated.isPaid ? Date() : nil
        let data = try SharedFormatters.jsonEncoderSeconds.encode(updated)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict, merge: true)
    }

    public func delete(_ item: BillItem) async throws {
        var items = ModuleLocalStore.loadBills()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveBills(items)
        try? JSONEntitySQLiteStore.sharedBills.delete(id: item.id)

        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(item.id).delete()
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
            return localItems
        }
        do {
            let snapshot = try await ref.order(by: "addedAt", descending: true).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(ShoppingItem.self, from: $0) }
            let merged = Self.merge(local: localItems, remote: remote)
            ModuleLocalStore.saveShopping(merged)
            return merged
        } catch {
            return localItems
        }
    }

    private static func merge(local: [ShoppingItem], remote: [ShoppingItem]) -> [ShoppingItem] {
        var byID = Dictionary.uniquingFirstValue(remote.map { ($0.id, $0) })
        for item in local where byID[item.id] == nil {
            byID[item.id] = item
        }
        return byID.values.sorted { $0.addedAt > $1.addedAt }
    }

    public func create(_ item: ShoppingItem) async throws {
        var items = ModuleLocalStore.loadShopping()
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
            ModuleLocalStore.saveShopping(items)
        }
        scheduleRemoteSave(item)
    }

    private func scheduleRemoteSave(_ item: ShoppingItem) {
        Task {
            guard let ref = firebase.userCollection(collection) else { return }
            var mutable = item
            mutable.userId = firebase.currentUserId ?? ""
            guard let data = try? SharedFormatters.jsonEncoderSeconds.encode(mutable),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            try? await ref.document(item.id).setData(dict)
        }
    }

    public func togglePurchased(_ item: ShoppingItem) async throws {
        var items = ModuleLocalStore.loadShopping()
        var updated = item
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPurchased.toggle()
            items[idx].purchasedAt = items[idx].isPurchased ? Date() : nil
            updated = items[idx]
            ModuleLocalStore.saveShopping(items)
        }

        guard let ref = firebase.userCollection(collection) else { return }
        let data = try SharedFormatters.jsonEncoderSeconds.encode(updated)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict, merge: true)
    }

    public func delete(_ item: ShoppingItem) async throws {
        var items = ModuleLocalStore.loadShopping()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveShopping(items)
        try? JSONEntitySQLiteStore.sharedShopping.delete(id: item.id)

        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(item.id).delete()
    }
}

// MARK: - Relationships Repository

@MainActor
public final class RelationshipRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "relationships"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    public func getAll(for userId: String) async throws -> [RelationshipContact] {
        let localItems = ModuleLocalStore.loadRelationships()
        guard let ref = firebase.userCollection(collection) else {
            return localItems
        }
        do {
            let snapshot = try await ref.getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(RelationshipContact.self, from: $0) }
            if !remote.isEmpty {
                ModuleLocalStore.saveRelationships(remote)
                return remote
            }
            return localItems
        } catch {
            return localItems
        }
    }

    public func create(_ item: RelationshipContact) async throws {
        var items = ModuleLocalStore.loadRelationships()
        items.append(item)
        ModuleLocalStore.saveRelationships(items)

        guard let ref = firebase.userCollection(collection) else { return }
        var mutable = item; mutable.userId = firebase.currentUserId ?? ""
        let data = try SharedFormatters.jsonEncoderSeconds.encode(mutable)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict)
    }

    public func logContact(_ contact: RelationshipContact) async throws {
        var items = ModuleLocalStore.loadRelationships()
        if let idx = items.firstIndex(where: { $0.id == contact.id }) {
            items[idx].lastContactedAt = Date()
            ModuleLocalStore.saveRelationships(items)
        }

        guard let ref = firebase.userCollection(collection) else { return }
        var updated = contact
        updated.lastContactedAt = Date()
        let data = try SharedFormatters.jsonEncoderSeconds.encode(updated)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(contact.id).setData(dict, merge: true)
    }

    public func delete(_ contact: RelationshipContact) async throws {
        var items = ModuleLocalStore.loadRelationships()
        items.removeAll { $0.id == contact.id }
        ModuleLocalStore.saveRelationships(items)
        try? JSONEntitySQLiteStore.sharedRelationships.delete(id: contact.id)

        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(contact.id).delete()
    }
}

// MARK: - Journaling Repository

@MainActor
public final class JournalRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "journal_entries"

    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }

    public func getAll(for userId: String) async throws -> [JournalEntry] {
        let localItems = ModuleLocalStore.loadJournal()
        guard let ref = firebase.userCollection(collection) else {
            return localItems
        }
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(JournalEntry.self, from: $0) }
            if !remote.isEmpty {
                ModuleLocalStore.saveJournal(remote)
                return remote
            }
            return localItems
        } catch {
            return localItems
        }
    }

    public func create(_ item: JournalEntry) async throws {
        var items = ModuleLocalStore.loadJournal()
        items.insert(item, at: 0)
        ModuleLocalStore.saveJournal(items)

        guard let ref = firebase.userCollection(collection) else { return }
        var mutable = item; mutable.userId = firebase.currentUserId ?? ""
        let data = try SharedFormatters.jsonEncoderSeconds.encode(mutable)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict)
    }

    public func delete(_ item: JournalEntry) async throws {
        var items = ModuleLocalStore.loadJournal()
        items.removeAll { $0.id == item.id }
        ModuleLocalStore.saveJournal(items)
        try? JSONEntitySQLiteStore.sharedJournal.delete(id: item.id)

        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(item.id).delete()
    }
}
