import Foundation
import WidgetKit
import LookAfterCore
import LookAfterData
import LookAfterAI
import ExecutiveBrain

/// Orchestrates a complete factory reset — every persisted layer except auth session and dev flags.
@MainActor
public final class FactoryResetManager {
    public static let shared = FactoryResetManager()

    private let local = LocalPersistenceManager.shared
    private let firebase = FirebaseManager.shared
    private let taskStore = TaskStore.shared

    private static let firestoreCollections = [
        "tasks",
        "inbox_items",
        "health_summaries",
        "energy_reports",
        "bills",
        "shopping_items",
        "relationships",
        "journal_entries",
        "task_deletions",
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
        CascadeActionLog.shared.clear()
        BriefingNarrativeCache.shared.clear()
        UserCalibrationStore.reset()
        HabitCompletionStore.reset()
        TaskStore.shared.resetLocalStore()
        try? InboxSQLiteStore.shared.reset()
        try? HealthSummarySQLiteStore.shared.reset()
        try? ModuleEntitySQLiteStore.shared.reset()
        TaskDeletionRegistry.reset()
        TaskSyncOutbox.shared.clearAll()
        CloudSyncOutbox.shared.clearAll()
        local.deleteAllJSONFiles()
        local.deleteBehaviorMemoryDirectory()
        local.clearApplicationCaches()

        wipeUserDefaultsExceptPreserved()
        // Bulk defaults wipe bypasses store.reset() — drop in-memory caches so loads re-read disk.
        UserLifeProfileStore.invalidateCache()
        LifeModelStore.invalidateCache()
        MedicationStore.invalidateCache()
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
        guard firebase.isCloudSyncAvailable else { return }

        await withTaskGroup(of: Void.self) { group in
            for collection in Self.firestoreCollections {
                group.addTask { await self.deleteAllDocuments(in: collection) }
            }
        }
    }

    /// Ends fresh-install guard after local wipe, cloud delete, and bootstrap complete.
    public func finishFreshInstall() {
        FreshInstallGuard.exit()
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
