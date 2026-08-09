import Foundation

// MARK: - Parked entry

/// A task that cascade Stage 4 (park) removed from the day — never a silent black hole.
public struct ParkedTaskEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { taskID }
    public var taskID: String
    public var title: String
    public var semanticHash: String?
    public var originalScheduledDate: Date?
    public var originalDurationMinutes: Int
    public var parkedAt: Date
    public var reason: String
    /// Soft constraint after parking — always fluid so re-integration can place freely.
    public var preferredConstraint: TimeConstraint
    /// Lifecycle after parking — active recovery vs decayed (14d+) vs archived someday.
    public var decayState: ParkedDecayState
    public var priority: Priority
    public var lifeArea: LifeArea

    public init(
        taskID: String,
        title: String,
        semanticHash: String? = nil,
        originalScheduledDate: Date? = nil,
        originalDurationMinutes: Int = 30,
        parkedAt: Date = Date(),
        reason: String = "cascade_park",
        preferredConstraint: TimeConstraint = .fluid,
        decayState: ParkedDecayState = .recoverable,
        priority: Priority = .medium,
        lifeArea: LifeArea = .personal
    ) {
        self.taskID = taskID
        self.title = title
        self.semanticHash = semanticHash
        self.originalScheduledDate = originalScheduledDate
        self.originalDurationMinutes = originalDurationMinutes
        self.parkedAt = parkedAt
        self.reason = reason
        self.preferredConstraint = preferredConstraint
        self.decayState = decayState
        self.priority = priority
        self.lifeArea = lifeArea
    }

    public func ageDays(now: Date = Date()) -> Double {
        now.timeIntervalSince(parkedAt) / 86_400
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try c.decode(String.self, forKey: .taskID)
        title = try c.decode(String.self, forKey: .title)
        semanticHash = try c.decodeIfPresent(String.self, forKey: .semanticHash)
        originalScheduledDate = try c.decodeIfPresent(Date.self, forKey: .originalScheduledDate)
        originalDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .originalDurationMinutes) ?? 30
        parkedAt = try c.decodeIfPresent(Date.self, forKey: .parkedAt) ?? Date()
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? "cascade_park"
        preferredConstraint = try c.decodeIfPresent(TimeConstraint.self, forKey: .preferredConstraint) ?? .fluid
        decayState = try c.decodeIfPresent(ParkedDecayState.self, forKey: .decayState) ?? .recoverable
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        lifeArea = try c.decodeIfPresent(LifeArea.self, forKey: .lifeArea) ?? .personal
    }

    private enum CodingKeys: String, CodingKey {
        case taskID, title, semanticHash, originalScheduledDate, originalDurationMinutes
        case parkedAt, reason, preferredConstraint, decayState, priority, lifeArea
    }
}

/// Fluid decay lifecycle for parked casualties.
public enum ParkedDecayState: String, Codable, Sendable, Equatable {
    /// Freshly parked — eligible for automatic re-integration.
    case recoverable
    /// >14 days — AI should ask delete vs someday (not auto-slotted).
    case decayed
    /// User chose someday/maybe; kept out of active bidding.
    case someday
    /// User deleted — retained briefly for undo then GC.
    case discarded
}

// MARK: - Queue envelope

public struct ParkedTaskQueueEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var entries: [ParkedTaskEntry]
    public var updatedAt: Date

    public static let currentSchemaVersion = 1

    public static func empty(now: Date = Date()) -> ParkedTaskQueueEnvelope {
        ParkedTaskQueueEnvelope(schemaVersion: currentSchemaVersion, entries: [], updatedAt: now)
    }

    public mutating func enqueue(_ entry: ParkedTaskEntry, now: Date = Date()) {
        entries.removeAll { $0.taskID == entry.taskID }
        entries.append(entry)
        updatedAt = now
    }

    public mutating func dequeue(taskID: String, now: Date = Date()) -> ParkedTaskEntry? {
        guard let idx = entries.firstIndex(where: { $0.taskID == taskID }) else { return nil }
        let entry = entries.remove(at: idx)
        updatedAt = now
        return entry
    }

    public mutating func update(_ entry: ParkedTaskEntry, now: Date = Date()) {
        if let idx = entries.firstIndex(where: { $0.taskID == entry.taskID }) {
            entries[idx] = entry
        }
        updatedAt = now
    }

    public var taskIDs: [String] { entries.map(\.taskID) }

    public var recoverableEntries: [ParkedTaskEntry] {
        entries.filter { $0.decayState == .recoverable }
    }

    public var decayedEntries: [ParkedTaskEntry] {
        entries.filter { $0.decayState == .decayed }
    }
}

// MARK: - Store

/// Local recovery queue for parked cascade casualties. Weekly review / AI briefing read this.
public final class ParkedTaskQueueStore: @unchecked Sendable {
    public static let shared = ParkedTaskQueueStore()

    private let lock = NSLock()
    private var envelope: ParkedTaskQueueEnvelope
    private let fileURL: URL?
    private let memoryOnly: Bool

    public init(directory: URL? = nil) {
        memoryOnly = false
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("parked_task_queue.json")
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            fileURL = support.appendingPathComponent("parked_task_queue.json")
        } else {
            fileURL = nil
        }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? SharedFormatters.jsonDecoderSeconds.decode(ParkedTaskQueueEnvelope.self, from: data) {
            envelope = loaded
        } else {
            envelope = .empty()
        }
    }

    public static func inMemory(seed: ParkedTaskQueueEnvelope = .empty()) -> ParkedTaskQueueStore {
        ParkedTaskQueueStore(memorySeed: seed)
    }

    private init(memorySeed: ParkedTaskQueueEnvelope) {
        memoryOnly = true
        fileURL = nil
        envelope = memorySeed
    }

    public func snapshot() -> ParkedTaskQueueEnvelope {
        lock.lock(); defer { lock.unlock() }
        return envelope
    }

    public func enqueue(_ entry: ParkedTaskEntry) {
        lock.lock()
        envelope.enqueue(entry)
        let snap = envelope
        lock.unlock()
        persist(snap)
    }

    public func enqueue(from task: LifeTask, reason: String = "cascade_park", now: Date = Date()) {
        enqueue(
            ParkedTaskEntry(
                taskID: task.id,
                title: task.title,
                semanticHash: BehavioralSemanticHash.make(for: task),
                originalScheduledDate: task.scheduledDate,
                originalDurationMinutes: task.estimatedMinutes,
                parkedAt: now,
                reason: reason,
                preferredConstraint: .fluid,
                decayState: .recoverable,
                priority: task.priority,
                lifeArea: task.lifeArea
            )
        )
    }

    @discardableResult
    public func dequeue(taskID: String) -> ParkedTaskEntry? {
        lock.lock()
        let entry = envelope.dequeue(taskID: taskID)
        let snap = envelope
        lock.unlock()
        persist(snap)
        return entry
    }

    /// Mark stale recoverable entries as decayed (default 14 days) for AI review.
    @discardableResult
    public func applyFluidDecay(
        now: Date = Date(),
        decayAfterDays: Double = 14,
        discardAfterDays: Double = 60
    ) -> (decayed: [ParkedTaskEntry], discarded: [String]) {
        lock.lock()
        var decayed: [ParkedTaskEntry] = []
        var discarded: [String] = []
        for idx in envelope.entries.indices {
            var entry = envelope.entries[idx]
            let age = entry.ageDays(now: now)
            if entry.decayState == .discarded, age >= discardAfterDays {
                discarded.append(entry.taskID)
                continue
            }
            if entry.decayState == .recoverable, age >= decayAfterDays {
                entry.decayState = .decayed
                envelope.entries[idx] = entry
                decayed.append(entry)
            }
        }
        envelope.entries.removeAll { discarded.contains($0.taskID) }
        envelope.updatedAt = now
        let snap = envelope
        lock.unlock()
        persist(snap)
        return (decayed, discarded)
    }

    public func markSomeday(taskID: String) {
        lock.lock()
        if var entry = envelope.entries.first(where: { $0.taskID == taskID }) {
            entry.decayState = .someday
            envelope.update(entry)
        }
        let snap = envelope
        lock.unlock()
        persist(snap)
    }

    public func markDiscarded(taskID: String) {
        lock.lock()
        if var entry = envelope.entries.first(where: { $0.taskID == taskID }) {
            entry.decayState = .discarded
            envelope.update(entry)
        }
        let snap = envelope
        lock.unlock()
        persist(snap)
    }

    /// FIFO recovery candidates (non-decayed only).
    public func candidatesForReintegration(limit: Int = 5) -> [ParkedTaskEntry] {
        lock.lock(); defer { lock.unlock() }
        return Array(
            envelope.recoverableEntries
                .sorted { $0.parkedAt < $1.parkedAt }
                .prefix(limit)
        )
    }

    /// Free-market auction — energy/TOD aware; may return empty under sabotage recovery.
    public func bidForGap(
        gapMinutes: Int,
        energy: EnergyLevel = .moderate,
        consecutiveHighLoadDays: Int = 0,
        sabotageCooldownActive: Bool = false,
        now: Date = Date(),
        limit: Int = 3
    ) -> GapAuctionOutcome {
        lock.lock()
        let pool = envelope.recoverableEntries
        lock.unlock()
        let context = GapAuctionContext(
            energy: energy,
            consecutiveHighLoadDays: consecutiveHighLoadDays,
            gapMinutes: gapMinutes,
            now: now,
            sabotageCooldownActive: sabotageCooldownActive
        )
        return GapAuctionEngine.run(pool: pool, context: context, limit: limit)
    }

    /// Backward-compatible winners list (ignores sabotage → empty array).
    public func bidWinners(
        gapMinutes: Int,
        energy: EnergyLevel = .moderate,
        consecutiveHighLoadDays: Int = 0,
        sabotageCooldownActive: Bool = false,
        now: Date = Date(),
        limit: Int = 3
    ) -> [ParkedTaskEntry] {
        switch bidForGap(
            gapMinutes: gapMinutes,
            energy: energy,
            consecutiveHighLoadDays: consecutiveHighLoadDays,
            sabotageCooldownActive: sabotageCooldownActive,
            now: now,
            limit: limit
        ) {
        case .filled(let winners): return winners
        case .sabotageRecovery, .empty: return []
        }
    }

    private func persist(_ snap: ParkedTaskQueueEnvelope) {
        guard !memoryOnly, let fileURL else { return }
        guard let data = try? SharedFormatters.jsonEncoderSeconds.encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
