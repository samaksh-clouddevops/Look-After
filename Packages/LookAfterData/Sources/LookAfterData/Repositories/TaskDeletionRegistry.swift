import Foundation

/// Tracks task ids deleted locally so Firestore merge cannot resurrect them.
/// Durable App Support file (not UserDefaults). Optionally mirrors tombstones to Firestore.
public enum TaskDeletionRegistry {
    private static let defaultsKey = "lifeos_deleted_task_ids"
    private static let maxEntries = 500
    private static let fileName = "deleted_task_ids.json"

    public static func markDeleted(_ id: String) {
        guard !id.isEmpty else { return }
        var ids = load()
        ids.insert(id)
        if ids.count > maxEntries {
            ids = Set(ids.sorted().suffix(maxEntries))
        }
        persist(ids)
        Task { @MainActor in
            await syncTombstoneToCloud(id: id)
        }
    }

    public static func load() -> Set<String> {
        migrateFromUserDefaultsIfNeeded()
        guard let data = try? Data(contentsOf: fileURL()),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(list)
    }

    public static func mergeRemote(_ remote: [String]) {
        var ids = load()
        ids.formUnion(remote)
        if ids.count > maxEntries {
            ids = Set(ids.sorted().suffix(maxEntries))
        }
        persist(ids)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        try? FileManager.default.removeItem(at: fileURL())
    }

    /// Pull cloud tombstones for this user and merge locally (multi-device).
    @MainActor
    public static func pullFromCloud(firebase: FirebaseManager = .shared) async {
        guard let ref = firebase.userCollection("task_deletions") else { return }
        do {
            let snapshot = try await ref.getDocuments()
            let remoteIds = snapshot.documents.map(\.documentID)
            if !remoteIds.isEmpty {
                mergeRemote(remoteIds)
            }
        } catch {
            // Local tombstones remain authoritative offline.
        }
    }

    @MainActor
    private static func syncTombstoneToCloud(id: String) async {
        guard let ref = FirebaseManager.shared.userCollection("task_deletions") else { return }
        do {
            try await ref.document(id).setData([
                "deletedAt": Date().timeIntervalSince1970,
            ], merge: true)
        } catch {
            // Local tombstone already saved; cloud retry on next pull/push cycle.
        }
    }

    private static func persist(_ ids: Set<String>) {
        do {
            let url = fileURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Array(ids))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } catch {
            #if DEBUG
            print("[TaskDeletionRegistry] persist failed: \(error)")
            #endif
        }
    }

    private static func migrateFromUserDefaultsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL().path),
              let legacy = UserDefaults.standard.stringArray(forKey: defaultsKey),
              !legacy.isEmpty else { return }
        persist(Set(legacy))
    }

    private static func fileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LookAfter", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
