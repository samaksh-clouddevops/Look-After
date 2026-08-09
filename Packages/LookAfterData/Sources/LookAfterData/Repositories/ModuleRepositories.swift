import Foundation
import FirebaseFirestore
import LookAfterCore

// MARK: - Finance & Bills Repository

@MainActor
public final class BillRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "bills"
    private let local = LocalPersistenceManager.shared
    
    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }
    
    public func getAll(for userId: String) async throws -> [BillItem] {
        guard let ref = firebase.userCollection(collection) else {
            return local.load([BillItem].self, filename: collection)
        }
        do {
            let snapshot = try await ref.order(by: "dueDate", descending: false).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(BillItem.self, from: $0) }
            if !remote.isEmpty { local.save(remote, filename: collection) }
            return remote.isEmpty ? local.load([BillItem].self, filename: collection) : remote
        } catch {
            return local.load([BillItem].self, filename: collection)
        }
    }
    
    public func create(_ item: BillItem) async throws {
        var items = local.load([BillItem].self, filename: collection)
        items.append(item)
        local.save(items, filename: collection)
        
        guard let ref = firebase.userCollection(collection) else { return }
        var mutable = item; mutable.userId = firebase.currentUserId ?? ""
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(mutable)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict)
    }
    
    public func togglePaid(_ item: BillItem) async throws {
        var items = local.load([BillItem].self, filename: collection)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPaid.toggle()
            items[idx].paidAt = items[idx].isPaid ? Date() : nil
            local.save(items, filename: collection)
        }
        
        guard let ref = firebase.userCollection(collection) else { return }
        var updated = item
        updated.isPaid.toggle()
        updated.paidAt = updated.isPaid ? Date() : nil
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(updated)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict, merge: true)
    }
    
    public func delete(_ item: BillItem) async throws {
        var items = local.load([BillItem].self, filename: collection)
        items.removeAll { $0.id == item.id }
        local.save(items, filename: collection)
        
        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(item.id).delete()
    }
}

// MARK: - Shopping & Inventory Repository

@MainActor
public final class ShoppingRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "shopping_items"
    private let local = LocalPersistenceManager.shared
    
    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }
    
    public func getAll(for userId: String) async throws -> [ShoppingItem] {
        let localItems = local.load([ShoppingItem].self, filename: collection)
        guard let ref = firebase.userCollection(collection) else {
            return localItems
        }
        do {
            let snapshot = try await ref.order(by: "addedAt", descending: true).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(ShoppingItem.self, from: $0) }
            let merged = Self.merge(local: localItems, remote: remote)
            local.save(merged, filename: collection)
            return merged
        } catch {
            print("[ShoppingList] Remote load failed, using local cache: \(error.localizedDescription)")
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
        var items = local.load([ShoppingItem].self, filename: collection)
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
            local.save(items, filename: collection)
        }

        // Persist locally first; sync to Firebase in the background so UI never blocks.
        scheduleRemoteSave(item)
    }

    private func scheduleRemoteSave(_ item: ShoppingItem) {
        Task {
            guard let ref = firebase.userCollection(collection) else { return }
            var mutable = item
            mutable.userId = firebase.currentUserId ?? ""
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard let data = try? encoder.encode(mutable),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            try? await ref.document(item.id).setData(dict)
        }
    }
    
    public func togglePurchased(_ item: ShoppingItem) async throws {
        var items = local.load([ShoppingItem].self, filename: collection)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPurchased.toggle()
            items[idx].purchasedAt = items[idx].isPurchased ? Date() : nil
            local.save(items, filename: collection)
        }
        
        guard let ref = firebase.userCollection(collection) else { return }
        var updated = item
        updated.isPurchased.toggle()
        updated.purchasedAt = updated.isPurchased ? Date() : nil
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(updated)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict, merge: true)
    }
    
    public func delete(_ item: ShoppingItem) async throws {
        var items = local.load([ShoppingItem].self, filename: collection)
        items.removeAll { $0.id == item.id }
        local.save(items, filename: collection)
        
        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(item.id).delete()
    }
}

// MARK: - Relationships Repository

@MainActor
public final class RelationshipRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "relationships"
    private let local = LocalPersistenceManager.shared
    
    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }
    
    public func getAll(for userId: String) async throws -> [RelationshipContact] {
        guard let ref = firebase.userCollection(collection) else {
            return local.load([RelationshipContact].self, filename: collection)
        }
        do {
            let snapshot = try await ref.getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(RelationshipContact.self, from: $0) }
            if !remote.isEmpty { local.save(remote, filename: collection) }
            return remote.isEmpty ? local.load([RelationshipContact].self, filename: collection) : remote
        } catch {
            return local.load([RelationshipContact].self, filename: collection)
        }
    }
    
    public func create(_ item: RelationshipContact) async throws {
        var items = local.load([RelationshipContact].self, filename: collection)
        items.append(item)
        local.save(items, filename: collection)
        
        guard let ref = firebase.userCollection(collection) else { return }
        var mutable = item; mutable.userId = firebase.currentUserId ?? ""
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(mutable)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict)
    }
    
    public func logContact(_ contact: RelationshipContact) async throws {
        var items = local.load([RelationshipContact].self, filename: collection)
        if let idx = items.firstIndex(where: { $0.id == contact.id }) {
            items[idx].lastContactedAt = Date()
            local.save(items, filename: collection)
        }
        
        guard let ref = firebase.userCollection(collection) else { return }
        var updated = contact
        updated.lastContactedAt = Date()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(updated)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(contact.id).setData(dict, merge: true)
    }
    
    public func delete(_ contact: RelationshipContact) async throws {
        var items = local.load([RelationshipContact].self, filename: collection)
        items.removeAll { $0.id == contact.id }
        local.save(items, filename: collection)
        
        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(contact.id).delete()
    }
}

// MARK: - Journaling Repository

@MainActor
public final class JournalRepository: ObservableObject {
    private let firebase: FirebaseManager
    private let collection = "journal_entries"
    private let local = LocalPersistenceManager.shared
    
    public init(firebase: FirebaseManager? = nil) { self.firebase = firebase ?? FirebaseManager.shared }
    
    public func getAll(for userId: String) async throws -> [JournalEntry] {
        guard let ref = firebase.userCollection(collection) else {
            return local.load([JournalEntry].self, filename: collection)
        }
        do {
            let snapshot = try await ref.order(by: "createdAt", descending: true).getDocuments()
            let remote = try snapshot.documents.compactMap { try firebase.decode(JournalEntry.self, from: $0) }
            if !remote.isEmpty { local.save(remote, filename: collection) }
            return remote.isEmpty ? local.load([JournalEntry].self, filename: collection) : remote
        } catch {
            return local.load([JournalEntry].self, filename: collection)
        }
    }
    
    public func create(_ item: JournalEntry) async throws {
        var items = local.load([JournalEntry].self, filename: collection)
        items.insert(item, at: 0)
        local.save(items, filename: collection)
        
        guard let ref = firebase.userCollection(collection) else { return }
        var mutable = item; mutable.userId = firebase.currentUserId ?? ""
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(mutable)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? await ref.document(item.id).setData(dict)
    }
    
    public func delete(_ item: JournalEntry) async throws {
        var items = local.load([JournalEntry].self, filename: collection)
        items.removeAll { $0.id == item.id }
        local.save(items, filename: collection)
        
        guard let ref = firebase.userCollection(collection) else { return }
        try? await ref.document(item.id).delete()
    }
}
