import Foundation

// MARK: - Someday entry

/// Long-term dormant ideas — psychological safety without operational DB bloat.
public struct SomedayVaultEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { taskID }
    public var taskID: String
    public var title: String
    public var notes: String
    public var lifeArea: LifeArea
    public var priority: Priority
    public var semanticHash: String?
    public var parkedAt: Date?
    public var movedAt: Date
    public var source: String

    public init(
        taskID: String,
        title: String,
        notes: String = "",
        lifeArea: LifeArea = .personal,
        priority: Priority = .someday,
        semanticHash: String? = nil,
        parkedAt: Date? = nil,
        movedAt: Date = Date(),
        source: String = "fluid_decay"
    ) {
        self.taskID = taskID
        self.title = title
        self.notes = notes
        self.lifeArea = lifeArea
        self.priority = priority
        self.semanticHash = semanticHash
        self.parkedAt = parkedAt
        self.movedAt = movedAt
        self.source = source
    }

    public init(from parked: ParkedTaskEntry, now: Date = Date()) {
        self.init(
            taskID: parked.taskID,
            title: parked.title,
            lifeArea: parked.lifeArea,
            priority: .someday,
            semanticHash: parked.semanticHash,
            parkedAt: parked.parkedAt,
            movedAt: now,
            source: "fluid_decay"
        )
    }
}

public struct SomedayVaultEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var entries: [SomedayVaultEntry]
    public var updatedAt: Date

    public static let currentSchemaVersion = 1

    public static func empty(now: Date = Date()) -> SomedayVaultEnvelope {
        SomedayVaultEnvelope(schemaVersion: currentSchemaVersion, entries: [], updatedAt: now)
    }

    public mutating func upsert(_ entry: SomedayVaultEntry, now: Date = Date()) {
        entries.removeAll { $0.taskID == entry.taskID }
        entries.append(entry)
        updatedAt = now
    }

    public mutating func remove(taskID: String, now: Date = Date()) {
        entries.removeAll { $0.taskID == taskID }
        updatedAt = now
    }
}

// MARK: - Store

public final class SomedayVaultStore: @unchecked Sendable {
    public static let shared = SomedayVaultStore()

    private let lock = NSLock()
    private var envelope: SomedayVaultEnvelope
    private let fileURL: URL?
    private let memoryOnly: Bool

    public init(directory: URL? = nil) {
        memoryOnly = false
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("someday_vault.json")
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            fileURL = support.appendingPathComponent("someday_vault.json")
        } else {
            fileURL = nil
        }
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(SomedayVaultEnvelope.self, from: data) {
            envelope = loaded
        } else {
            envelope = .empty()
        }
    }

    public static func inMemory(seed: SomedayVaultEnvelope = .empty()) -> SomedayVaultStore {
        SomedayVaultStore(memorySeed: seed)
    }

    private init(memorySeed: SomedayVaultEnvelope) {
        memoryOnly = true
        fileURL = nil
        envelope = memorySeed
    }

    public func snapshot() -> SomedayVaultEnvelope {
        lock.lock(); defer { lock.unlock() }
        return envelope
    }

    public func add(_ entry: SomedayVaultEntry) {
        lock.lock()
        envelope.upsert(entry)
        let snap = envelope
        lock.unlock()
        persist(snap)
    }

    public func add(from parked: ParkedTaskEntry, now: Date = Date()) {
        add(SomedayVaultEntry(from: parked, now: now))
    }

    public func remove(taskID: String) {
        lock.lock()
        envelope.remove(taskID: taskID)
        let snap = envelope
        lock.unlock()
        persist(snap)
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return envelope.entries.count
    }

    private func persist(_ snap: SomedayVaultEnvelope) {
        guard !memoryOnly, let fileURL else { return }
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
