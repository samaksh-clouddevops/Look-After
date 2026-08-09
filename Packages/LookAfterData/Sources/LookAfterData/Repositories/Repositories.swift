import Foundation
import FirebaseFirestore
import LookAfterCore
import os

/// Repository for managing tasks in Firestore.
@MainActor
public final class TaskRepository: ObservableObject {
    
    private let firebase: FirebaseManager
    private let collection = "tasks"
    private let taskStore: TaskSQLiteStore
    private static let cloudReadTimeoutSeconds: TimeInterval = 8
    /// Shared across instances — migration/reassign must not leave stale per-instance caches.
    private static var cachedAll: [LifeTask]?

    public static func invalidateLocalCache() {
        cachedAll = nil
    }

    /// True when the in-memory local task list has been populated (warm or empty write).
    public static var hasWarmedLocalCache: Bool {
        cachedAll != nil
    }

    public init(firebase: FirebaseManager? = nil, taskStore: TaskSQLiteStore? = nil) {
        self.firebase = firebase ?? FirebaseManager.shared
        self.taskStore = taskStore ?? .shared
    }

    /// Loads `tasks.sqlite` off the main thread into `cachedAll`.
    /// Call once before first `localSnapshot` / `localAllTasks` on a cold process.
    /// Safe to call repeatedly — no-ops when already warm (unless `force` is true).
    @discardableResult
    public func warmLocalCache(force: Bool = false) async -> [LifeTask] {
        if !force, let cached = Self.cachedAll {
            return cached
        }
        let loaded = await taskStore.loadAllAsync()
        if force {
            // Explicit reload from disk (tests / recovery). May race with concurrent saves.
            Self.cachedAll = loaded
            TaskPersistenceLog.localLoad(count: loaded.count, userId: "warm-cache-force")
            return loaded
        }
        // Prefer a cache written by a concurrent mutator (create/save) during the await.
        // Only adopt disk if cache is still cold — never clobber fresher in-memory writes.
        if let cached = Self.cachedAll {
            return cached
        }
        Self.cachedAll = loaded
        TaskPersistenceLog.localLoad(count: loaded.count, userId: "warm-cache")
        return loaded
    }

    // MARK: - CRUD

    /// Instant read from on-device cache — no network.
    /// Requires `await warmLocalCache()` before first use on a cold process.
    public func localSnapshot(for userId: String) -> TaskListSnapshot {
        let tasks = tasksForUser(userId)
        TaskPersistenceLog.localLoad(count: tasks.count, userId: userId)
        let snapshot = TaskListSnapshot.make(from: tasks)
        TaskPersistenceLog.filterApplied(active: snapshot.active.count, completedToday: snapshot.completedToday.count)
        return snapshot
    }

    /// All locally persisted tasks for a user — includes completed history beyond today.
    public func localAllTasks(for userId: String) -> [LifeTask] {
        migrateAllTasksToCanonicalUserId()
        return tasksForUser(userId)
    }

    /// Moves tasks saved under a pre-auth fallback id to the real Firebase UID.
    public func reassignTasks(from oldUserId: String, to newUserId: String) {
        guard !oldUserId.isEmpty, !newUserId.isEmpty, oldUserId != newUserId else { return }

        var tasks = allLocalTasks()
        var changed = false

        for index in tasks.indices {
            guard tasks[index].userId == oldUserId else { continue }
            tasks[index].userId = newUserId
            changed = true
        }

        if changed {
            persistAllLocally(tasks)
        }
    }

    /// Reassigns any orphaned tasks to the current Firebase Auth UID.
    public func migrateAllTasksToCanonicalUserId() {
        let canonicalId = firebase.resolvedUserId
        guard !canonicalId.isEmpty else { return }

        let all = allLocalTasks()
        let staleIds = Set(all.map(\.userId).filter { !$0.isEmpty && $0 != canonicalId })
        for staleId in staleIds {
            reassignTasks(from: staleId, to: canonicalId)
        }
    }

    /// Single fetch for active + completed-today lists (avoids duplicate Firestore reads).
    public func getTaskLists(for userId: String) async throws -> TaskListSnapshot {
        let all = try await getAll(for: userId)
        let filtered = tasksForUser(all, userId: userId)
        let snapshot = TaskListSnapshot.make(from: filtered)
        TaskPersistenceLog.filterApplied(active: snapshot.active.count, completedToday: snapshot.completedToday.count)
        return snapshot
    }
    
    public func getAll(for userId: String) async throws -> [LifeTask] {
        let localTasks = tasksForUser(userId)
        if FreshInstallGuard.isActive {
            TaskPersistenceLog.fetchFinished(count: localTasks.count, merged: false)
            return localTasks
        }
        TaskPersistenceLog.fetchStarted(source: "getAll")
        
        guard let ref = firebase.userCollection(collection) else {
            TaskPersistenceLog.fetchFinished(count: localTasks.count, merged: false)
            return localTasks
        }

        do {
            let snapshot = try await AsyncTimeout.withTimeout(seconds: Self.cloudReadTimeoutSeconds) {
                try await ref
                    .order(by: "createdAt", descending: true)
                    .getDocuments()
            }
            let remote = try snapshot.documents.compactMap { try firebase.decode(LifeTask.self, from: $0) }
            var merged = TaskMerge.merge(local: allLocalTasks(), remote: remote)
            for index in merged.indices {
                ScheduleNormalization.normalizeFields(&merged[index])
            }
            persistAllLocally(merged)
            var result = tasksForUser(userId)
            for task in localTasks where !result.contains(where: { $0.id == task.id }) {
                result.append(task)
            }
            TaskPersistenceLog.fetchFinished(count: result.count, merged: !remote.isEmpty)
            return result
        } catch {
            TaskPersistenceLog.fetchFailed(error)
            TaskPersistenceLog.fetchFinished(count: localTasks.count, merged: false)
            return localTasks
        }
    }
    
    public func getActive(for userId: String) async throws -> [LifeTask] {
        try await getTaskLists(for: userId).active
    }
    
    public func getCompletedToday(for userId: String) async throws -> [LifeTask] {
        try await getTaskLists(for: userId).completedToday
    }
    
    public func create(_ task: LifeTask) async throws {
        var mutableTask = task
        ScheduleNormalization.normalizeFields(&mutableTask)
        let explicitUserId = task.userId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitUserId.isEmpty {
            mutableTask.userId = explicitUserId
        } else if let currentUserId = firebase.currentUserId, !currentUserId.isEmpty {
            mutableTask.userId = currentUserId
        } else {
            mutableTask.userId = firebase.resolvedUserId
        }
        try await saveLocallyAwait(mutableTask)
        TaskPersistenceLog.create(mutableTask)
        syncTaskToFirestore(mutableTask)
    }

    public func update(_ task: LifeTask) async throws {
        var mutableTask = task
        ScheduleNormalization.normalizeFields(&mutableTask)
        mutableTask.updatedAt = Date()
        try await saveLocallyAwait(mutableTask)
        TaskPersistenceLog.update(mutableTask)
        syncTaskToFirestore(mutableTask, merge: true)
    }

    /// Batch local update — upsert only touched rows (PERF-005 / PERF-011).
    public func updateMany(_ tasks: [LifeTask]) async throws {
        guard !tasks.isEmpty else { return }
        let deleted = TaskDeletionRegistry.load()
        var touched: [LifeTask] = []
        for var task in tasks {
            guard !deleted.contains(task.id) else { continue }
            ScheduleNormalization.normalizeFields(&task)
            task.updatedAt = Date()
            touched.append(task)
        }
        guard !touched.isEmpty else { return }

        var working = allLocalTasks()
        let touchedByID = Dictionary.uniquingFirstValue(touched.map { ($0.id, $0) })
        for (index, existing) in working.enumerated() {
            if let updated = touchedByID[existing.id] {
                working[index] = updated
            }
        }
        for task in touched where !working.contains(where: { $0.id == task.id }) {
            working.insert(task, at: 0)
        }

        try await taskStore.upsertMany(touched)
        Self.cachedAll = working
        TaskPersistenceLog.localSave(count: working.count)
        for task in touched {
            TaskPersistenceLog.update(task)
            syncTaskToFirestore(task, merge: true)
        }
    }

    public func delete(_ id: String) async throws {
        TaskDeletionRegistry.markDeleted(id)
        var tasks = allLocalTasks()
        tasks.removeAll { $0.id == id }
        try await taskStore.deleteId(id)
        Self.cachedAll = tasks
        TaskPersistenceLog.delete(id)
        TaskPersistenceLog.localSave(count: tasks.count)
        deleteTaskFromFirestore(id)
    }

    /// Push task to Firestore without blocking the caller.
    private func syncTaskToFirestore(_ task: LifeTask, merge: Bool = false) {
        Task {
            guard let ref = firebase.userCollection(collection) else { return }

            do {
                let data = try SharedFormatters.jsonEncoderSeconds.encode(task)
                guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                if merge {
                    try await ref.document(task.id).setData(dict, merge: true)
                } else {
                    try await ref.document(task.id).setData(dict)
                }
            } catch {
                // Local copy is already saved; cloud sync can retry later.
            }
        }
    }

    private func deleteTaskFromFirestore(_ id: String) {
        Task {
            guard let ref = firebase.userCollection(collection) else { return }
            try? await ref.document(id).delete()
        }
    }

    private func saveLocally(_ task: LifeTask) {
        guard !TaskDeletionRegistry.load().contains(task.id) else { return }
        var tasks = allLocalTasks()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        Self.cachedAll = tasks
        TaskPersistenceLog.localSave(count: tasks.count)
        // Fire-and-forget single-row upsert (PERF-011).
        let store = taskStore
        Task.detached(priority: .userInitiated) {
            try? await store.upsert(task)
        }
    }

    private func saveLocallyAwait(_ task: LifeTask) async throws {
        guard !TaskDeletionRegistry.load().contains(task.id) else { return }
        var tasks = allLocalTasks()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        try await taskStore.upsert(task)
        Self.cachedAll = tasks
        TaskPersistenceLog.localSave(count: tasks.count)
    }

    private static let perfLog = OSLog(subsystem: "com.samaksh.flowos.app", category: "TaskRepository")

    private func allLocalTasks() -> [LifeTask] {
        if let cached = Self.cachedAll { return cached }
#if DEBUG
        os_log(
            "allLocalTasks() before warmLocalCache() — returning empty (no main-thread disk read)",
            log: Self.perfLog,
            type: .debug
        )
#endif
        return []
    }

    /// Best-effort cache + async full replace (reassign / merge paths only).
    private func persistAllLocally(_ tasks: [LifeTask]) {
        Self.cachedAll = tasks
        TaskPersistenceLog.localSave(count: tasks.count)
        taskStore.replaceAllAsync(tasks)
    }

    /// Full rewrite — compact / forced rebuild only.
    private func persistAllLocallyAwait(_ tasks: [LifeTask]) async throws {
        try await taskStore.replaceAllAwait(tasks)
        Self.cachedAll = tasks
        TaskPersistenceLog.localSave(count: tasks.count)
    }

    /// Clears on-device task cache (factory reset).
    public func resetLocalStore() {
        TaskDeletionRegistry.reset()
        try? taskStore.replaceAllSync([])
        Self.cachedAll = []
        TaskPersistenceLog.localSave(count: 0)
    }

    /// Skips Firestore merge until cloud wipe completes — prevents old data reappearing.
    public func enterFreshInstallMode() {
        FreshInstallGuard.enter()
        try? taskStore.replaceAllSync([])
        Self.cachedAll = []
        TaskPersistenceLog.localSave(count: 0)
    }

    public func exitFreshInstallMode() {
        FreshInstallGuard.exit()
    }

    private func tasksForUser(_ userId: String) -> [LifeTask] {
        tasksForUser(allLocalTasks(), userId: userId)
    }

    private func tasksForUser(_ tasks: [LifeTask], userId: String) -> [LifeTask] {
        let deletedIDs = TaskDeletionRegistry.load()
        let visible = tasks.filter { !deletedIDs.contains($0.id) }
        guard !userId.isEmpty else { return visible }
        return visible.filter { $0.userId.isEmpty || $0.userId == userId }
    }

    /// Drops terminal recurrence rows and duplicate same-day instances that bloat local storage.
    @discardableResult
    public func compactRecurrenceStorage(
        for userId: String,
        retentionDays: Int
    ) -> Int {
        let all = allLocalTasks()
        let (pruned, removed) = TaskRecurrenceCompactor.compact(all, retentionDays: retentionDays)
        guard removed > 0 else { return 0 }
        persistAllLocally(pruned)
        print("[Tasks] compacted \(removed) recurrence rows (\(all.count) → \(pruned.count))")
        return removed
    }

    /// Background-safe compaction — loads/saves off the main actor's critical path.
    @discardableResult
    public func compactRecurrenceStorageAsync(
        for userId: String,
        retentionDays: Int
    ) async -> Int {
        let all: [LifeTask]
        if let cached = Self.cachedAll {
            all = cached
        } else {
            all = await taskStore.loadAllAsync()
            Self.cachedAll = all
        }

        let before = all.count
        let (pruned, removed) = await Task.detached(priority: .utility) {
            TaskRecurrenceCompactor.compact(all, retentionDays: retentionDays)
        }.value
        guard removed > 0 else { return 0 }
        do {
            try await taskStore.replaceAllAwait(pruned)
            Self.cachedAll = pruned
            print("[Tasks] compacted \(removed) recurrence rows (\(before) → \(pruned.count))")
            return removed
        } catch {
            print("[Tasks] compaction save failed: \(error.localizedDescription)")
            return 0
        }
    }

    /// Backward-compatible alias.
    @discardableResult
    public func pruneTerminalRecurrenceOccurrences(
        for userId: String,
        retentionDays: Int
    ) -> Int {
        compactRecurrenceStorage(for: userId, retentionDays: retentionDays)
    }
}

/// Repository for managing inbox items in Firestore.
@MainActor
public final class InboxRepository: ObservableObject {
    
    private let firebase: FirebaseManager
    private let collection = "inbox_items"
    
    public init(firebase: FirebaseManager? = nil) {
        self.firebase = firebase ?? FirebaseManager.shared
    }
    
    public func getAll(for userId: String) async throws -> [InboxItem] {
        guard let ref = firebase.userCollection(collection) else {
            throw FirebaseManagerError.notAuthenticated
        }
        
        let snapshot = try await ref
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { doc in
            try firebase.decode(InboxItem.self, from: doc)
        }
    }
    
    public func getUnprocessed(for userId: String) async throws -> [InboxItem] {
        guard let ref = firebase.userCollection(collection) else {
            throw FirebaseManagerError.notAuthenticated
        }
        
        let snapshot = try await ref
            .whereField("status", isEqualTo: "Unprocessed")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return try snapshot.documents.compactMap { doc in
            try firebase.decode(InboxItem.self, from: doc)
        }
    }
    
    public func create(_ item: InboxItem) async throws {
        guard let ref = firebase.userCollection(collection) else {
            throw FirebaseManagerError.notAuthenticated
        }
        
        var mutableItem = item
        mutableItem.userId = firebase.currentUserId ?? ""
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(mutableItem)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseManagerError.encodingError
        }
        
        try await ref.document(item.id).setData(dict)
    }
    
    public func update(_ item: InboxItem) async throws {
        guard let ref = firebase.userCollection(collection) else {
            throw FirebaseManagerError.notAuthenticated
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(item)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseManagerError.encodingError
        }
        
        try await ref.document(item.id).setData(dict, merge: true)
    }
    
    public func delete(_ id: String) async throws {
        guard let ref = firebase.userCollection(collection) else {
            throw FirebaseManagerError.notAuthenticated
        }
        
        try await ref.document(id).delete()
    }
}

/// Repository for health summaries.
@MainActor
public final class HealthSummaryRepository: ObservableObject {
    
    private let firebase: FirebaseManager
    private let local = LocalPersistenceManager.shared
    private let collection = "health_summaries"
    private static let cloudReadTimeoutSeconds: TimeInterval = 10
    private static let cloudWriteTimeoutSeconds: TimeInterval = 15
    
    public init(firebase: FirebaseManager? = nil) {
        self.firebase = firebase ?? FirebaseManager.shared
    }
    
    /// Saves locally first (milliseconds), then uploads to Firestore in the background.
    public func save(_ summary: HealthSummary) async throws {
        var mutableSummary = summary
        let resolvedId = firebase.resolvedUserId
        if !resolvedId.isEmpty {
            mutableSummary.userId = resolvedId
        } else if mutableSummary.userId.isEmpty {
            mutableSummary.userId = firebase.currentUserId ?? ""
        }
        saveLocally(mutableSummary)
        syncToFirestore(mutableSummary)
    }

    /// Moves summaries saved under a pre-auth fallback id to the real Firebase UID.
    public func reassignSummaries(from oldUserId: String, to newUserId: String) {
        guard !oldUserId.isEmpty, !newUserId.isEmpty, oldUserId != newUserId else { return }

        var summaries = local.load([HealthSummary].self, filename: collection)
        var changed = false

        for index in summaries.indices {
            guard summaries[index].userId == oldUserId else { continue }
            summaries[index].userId = newUserId
            if summaries[index].id.hasPrefix("\(oldUserId)-") {
                summaries[index].id = summaries[index].id.replacingOccurrences(of: oldUserId, with: newUserId)
            } else if summaries[index].id == oldUserId || summaries[index].id.isEmpty {
                summaries[index].id = Self.dailyDocumentId(for: summaries[index].date, userId: newUserId)
            }
            changed = true
        }

        if changed {
            summaries.sort { $0.date > $1.date }
            local.save(summaries, filename: collection)
        }
    }
    
    public func getLatest(for userId: String) async throws -> HealthSummary? {
        if FreshInstallGuard.isActive { return nil }

        migrateAllSummariesToCanonicalUserId()

        let canonicalId = firebase.resolvedUserId
        let resolvedId = !canonicalId.isEmpty ? canonicalId : (userId.isEmpty ? "" : userId)
        var localLatest = latestLocal(for: resolvedId)

        if localLatest == nil || (localLatest.map { Self.healthSignalScore($0) } ?? 0) == 0 {
            if let orphan = latestLocalWithHealthSignal(excludingUserId: resolvedId.isEmpty ? nil : resolvedId) {
                let targetId = !canonicalId.isEmpty ? canonicalId : resolvedId
                if !targetId.isEmpty, orphan.userId != targetId {
                    reassignSummaries(from: orphan.userId, to: targetId)
                    localLatest = latestLocal(for: targetId)
                } else {
                    localLatest = orphan
                }
            }
        }

        guard let ref = firebase.userCollection(collection) else {
            return Self.summaryWithHealthSignal(localLatest)
        }

        do {
            let snapshot = try await AsyncTimeout.withTimeout(seconds: Self.cloudReadTimeoutSeconds) {
                try await ref
                    .order(by: "date", descending: true)
                    .limit(to: 1)
                    .getDocuments()
            }

            guard let doc = snapshot.documents.first else {
                return Self.summaryWithHealthSignal(localLatest)
            }
            let remote = try firebase.decode(HealthSummary.self, from: doc)
            let preferred = Self.preferredSummary(local: localLatest, remote: remote)
            if let preferred, Self.healthSignalScore(preferred) > 0 {
                saveLocally(preferred)
                return preferred
            }
            return Self.summaryWithHealthSignal(localLatest)
        } catch {
            return Self.summaryWithHealthSignal(localLatest)
        }
    }

    /// Reassigns any orphaned summaries to the current Firebase Auth UID.
    public func migrateAllSummariesToCanonicalUserId() {
        let canonicalId = firebase.resolvedUserId
        guard !canonicalId.isEmpty else { return }

        let all = local.load([HealthSummary].self, filename: collection)
        let staleIds = Set(all.map(\.userId).filter { !$0.isEmpty && $0 != canonicalId })
        for staleId in staleIds {
            reassignSummaries(from: staleId, to: canonicalId)
        }
    }

    private static func summaryWithHealthSignal(_ summary: HealthSummary?) -> HealthSummary? {
        guard let summary, healthSignalScore(summary) > 0 else { return nil }
        return summary
    }

    /// Prefer the summary that actually contains HealthKit signal — cloud can lag behind a fresh local import.
    private static func preferredSummary(local: HealthSummary?, remote: HealthSummary?) -> HealthSummary? {
        switch (local, remote) {
        case (nil, nil):
            return nil
        case (let local?, nil):
            return local
        case (nil, let remote?):
            return remote
        case (let local?, let remote?):
            let localScore = healthSignalScore(local)
            let remoteScore = healthSignalScore(remote)
            if localScore != remoteScore {
                return localScore > remoteScore ? local : remote
            }
            return local.date >= remote.date ? local : remote
        }
    }

    private static func healthSignalScore(_ summary: HealthSummary) -> Int {
        var score = 0
        if (summary.totalSleepMinutes ?? 0) > 0 { score += 4 }
        if (summary.stepCount ?? 0) > 0 { score += 2 }
        if summary.restingHeartRate != nil || summary.averageHeartRate != nil { score += 2 }
        if summary.hrvAverage != nil { score += 1 }
        if (summary.workoutCount ?? 0) > 0 { score += 1 }
        return score
    }

    public static func dailyDocumentId(for date: Date, userId: String) -> String {
        let day = Calendar.current.startOfDay(for: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dayKey = formatter.string(from: day)
        return userId.isEmpty ? dayKey : "\(userId)-\(dayKey)"
    }

    private func latestLocalWithHealthSignal(excludingUserId: String?) -> HealthSummary? {
        let all = local.load([HealthSummary].self, filename: collection)
            .filter { summary in
                if let excludingUserId, summary.userId == excludingUserId { return false }
                return Self.healthSignalScore(summary) > 0
            }
            .sorted { $0.date > $1.date }
        return all.first
    }
    
    public func getForDateRange(from: Date, to: Date, userId: String) async throws -> [HealthSummary] {
        if FreshInstallGuard.isActive { return [] }

        let localSummaries = summaries(for: userId).filter { $0.date >= from && $0.date <= to }
        
        guard let ref = firebase.userCollection(collection) else {
            return localSummaries
        }
        
        do {
            let snapshot = try await AsyncTimeout.withTimeout(seconds: Self.cloudReadTimeoutSeconds) {
                try await ref
                    .order(by: "date", descending: true)
                    .getDocuments()
            }
            
            let remote = try snapshot.documents.compactMap { doc in
                try firebase.decode(HealthSummary.self, from: doc)
            }.filter { $0.date >= from && $0.date <= to }
            
            if !remote.isEmpty {
                mergeLocally(remote)
                return remote
            }
            return localSummaries
        } catch {
            return localSummaries
        }
    }
    
    private func saveLocally(_ summary: HealthSummary) {
        var summaries = local.load([HealthSummary].self, filename: collection)
        if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
            summaries[index] = summary
        } else {
            summaries.insert(summary, at: 0)
        }
        local.save(summaries, filename: collection)
    }
    
    private func mergeLocally(_ incoming: [HealthSummary]) {
        var summaries = local.load([HealthSummary].self, filename: collection)
        for summary in incoming {
            if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
                summaries[index] = summary
            } else {
                summaries.append(summary)
            }
        }
        summaries.sort { $0.date > $1.date }
        local.save(summaries, filename: collection)
    }
    
    private func summaries(for userId: String) -> [HealthSummary] {
        let all = local.load([HealthSummary].self, filename: collection)
        guard !userId.isEmpty else { return all.sorted { $0.date > $1.date } }
        return all.filter { $0.userId.isEmpty || $0.userId == userId }.sorted { $0.date > $1.date }
    }
    
    private func latestLocal(for userId: String) -> HealthSummary? {
        summaries(for: userId).first
    }
    
    private func syncToFirestore(_ summary: HealthSummary) {
        Task {
            guard let ref = firebase.userCollection(collection) else { return }
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                let data = try encoder.encode(summary)
                guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                
                try await AsyncTimeout.withTimeout(seconds: Self.cloudWriteTimeoutSeconds) {
                    try await ref.document(summary.id).setData(dict)
                }
            } catch {
                // Local copy is already saved; cloud sync can retry on next sync.
            }
        }
    }
}

/// Repository for energy reports.
@MainActor
public final class EnergyReportRepository: ObservableObject {
    
    private let firebase: FirebaseManager
    private let collection = "energy_reports"
    
    public init(firebase: FirebaseManager? = nil) {
        self.firebase = firebase ?? FirebaseManager.shared
    }
    
    public func save(_ report: EnergyReport) async throws {
        guard let ref = firebase.userCollection(collection) else {
            throw FirebaseManagerError.notAuthenticated
        }
        
        var mutableReport = report
        mutableReport.userId = firebase.currentUserId ?? ""
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(mutableReport)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseManagerError.encodingError
        }
        
        try await ref.document(report.id).setData(dict)
    }
    
    public func getToday(for userId: String) async throws -> [EnergyReport] {
        if FreshInstallGuard.isActive { return [] }

        guard let ref = firebase.userCollection(collection) else {
            throw FirebaseManagerError.notAuthenticated
        }
        
        let snapshot = try await ref
            .order(by: "timestamp", descending: true)
            .getDocuments()
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return try snapshot.documents.compactMap { doc in
            try firebase.decode(EnergyReport.self, from: doc)
        }.filter { $0.timestamp >= startOfDay }
    }
}
