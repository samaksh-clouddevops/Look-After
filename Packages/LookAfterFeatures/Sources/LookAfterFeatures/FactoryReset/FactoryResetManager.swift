import Foundation
import WidgetKit
import LookAfterCore
import LookAfterData
import ExecutiveBrain

/// Orchestrates a complete factory reset — every persisted layer except API keys and dev flags.
@MainActor
public final class FactoryResetManager {
    public static let shared = FactoryResetManager()

    private let local = LocalPersistenceManager.shared
    private let firebase = FirebaseManager.shared
    private let taskRepo = TaskRepository()

    private static let firestoreCollections = [
        "tasks",
        "inbox_items",
        "health_summaries",
        "energy_reports",
        "bills",
        "shopping_items",
        "relationships",
        "journal_entries",
    ]

    private static let moduleUserDefaultsPrefixes = [
        "lifeos.",
        "briefing",
        "executiveBrain.",
        "saved_coach",
        "saved_user",
        "healthLastSync",
        "flowDirector",
    ]

    private init() {}

    // MARK: - Public API

    /// Phase 1 — synchronous local wipe. UI should update immediately after this.
    public func performLocalReset(userId: String) {
        FreshInstallGuard.enter()
        taskRepo.resetLocalStore()
        local.deleteAllJSONFiles()
        local.deleteBehaviorMemoryDirectory()
        local.clearApplicationCaches()

        wipeUserDefaultsExceptPreserved()
        clearAllResumeSnapshots()
        DecisionHistoryStore.shared.clearAll()
        AnalyticsCacheManager.shared.invalidateAll()
        if !userId.isEmpty {
            AnalyticsCacheManager.shared.invalidate(userId: userId)
        }

        WidgetDataStore.clear()
        WidgetCenter.shared.reloadAllTimelines()

        UserDefaults.standard.set(true, forKey: FactoryResetPreservation.freshStartFlagKey)
        UserDefaults.standard.synchronize()
    }

    /// Phase 2 — cloud wipe (background). Skipped when Firestore is unavailable (mock/offline).
    public func resetCloudIfAvailable() async {
        defer { FreshInstallGuard.exit() }
        guard firebase.isCloudSyncAvailable else { return }

        await withTaskGroup(of: Void.self) { group in
            for collection in Self.firestoreCollections {
                group.addTask { await self.deleteAllDocuments(in: collection) }
            }
        }
    }

    public var isPendingFreshStart: Bool {
        UserDefaults.standard.bool(forKey: FactoryResetPreservation.freshStartFlagKey)
    }

    public func clearPendingFreshStart() {
        UserDefaults.standard.removeObject(forKey: FactoryResetPreservation.freshStartFlagKey)
    }

    // MARK: - Private

    private func wipeUserDefaultsExceptPreserved() {
        let preserved = FactoryResetPreservation.userDefaultsKeys
        let domain = Bundle.main.bundleIdentifier ?? ""
        if !domain.isEmpty, let dict = UserDefaults.standard.persistentDomain(forName: domain) {
            for key in dict.keys where !preserved.contains(key) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        if let groupDefaults = UserDefaults(suiteName: WidgetAppGroup.identifier) {
            groupDefaults.removeObject(forKey: WidgetAppGroup.snapshotKey)
        }
    }

    private func clearAllResumeSnapshots() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("lifeos.resume.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func deleteAllDocuments(in collection: String) async {
        guard let ref = firebase.userCollection(collection) else { return }
        guard let snapshot = try? await ref.getDocuments() else { return }

        await withTaskGroup(of: Void.self) { group in
            for document in snapshot.documents {
                group.addTask {
                    try? await document.reference.delete()
                }
            }
        }
    }
}
