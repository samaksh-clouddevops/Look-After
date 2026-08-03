import Foundation

/// Tracks task ids deleted locally so Firestore merge cannot resurrect them.
enum TaskDeletionRegistry {
    private static let key = "lifeos_deleted_task_ids"
    private static let maxEntries = 500

    static func markDeleted(_ id: String) {
        guard !id.isEmpty else { return }
        var ids = load()
        ids.insert(id)
        if ids.count > maxEntries {
            ids = Set(ids.sorted().suffix(maxEntries))
        }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
