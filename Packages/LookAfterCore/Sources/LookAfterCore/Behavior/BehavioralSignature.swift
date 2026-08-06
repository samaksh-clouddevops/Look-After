import Foundation

// MARK: - Lifecycle state

/// Progressive pruning lifecycle for vault signatures.
public enum SignatureState: Codable, Sendable, Equatable {
    case active
    /// Entered after 30 days of inactivity; deleted ~15 days later (45 total).
    case dormant(since: Date)

    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    public var dormantSince: Date? {
        if case .dormant(let since) = self { return since }
        return nil
    }

    private enum CodingKeys: String, CodingKey { case active, dormantSince }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let since = try c.decodeIfPresent(Date.self, forKey: .dormantSince) {
            self = .dormant(since: since)
        } else {
            self = .active
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .active:
            try c.encode(true, forKey: .active)
        case .dormant(let since):
            try c.encode(false, forKey: .active)
            try c.encode(since, forKey: .dormantSince)
        }
    }
}

// MARK: - Vault signature

/// Learned default time-lock for a *class* of tasks (semantic hash).
/// Segregated from operational `LifeTask` — never mutate primary timeline models here.
///
/// Persisted as Codable JSON (Behavior Memory pattern). LookAfterCore stays free of SwiftUI/SwiftData.
public struct BehavioralSignature: Codable, Sendable, Equatable, Identifiable {
    /// Unique class key, e.g. `physicalActivity|gym_push_day`.
    public var semanticHash: String
    /// Current AI-assumed default constraint for this class.
    public var learnedConstraint: TimeConstraint
    /// Rolling count of manual overrides since last baseline flip / reset.
    public var overrideCount: Int
    /// Time-of-day confidence that `learnedConstraint` is correct.
    public var confidence: TemporalConfidence
    public var lastUpdated: Date
    public var createdAt: Date
    /// Last time this hash appeared in telemetry or an operational schedule (pruning anchor).
    public var lastSeenInSchedule: Date?
    /// Active vs dormant pruning state.
    public var state: SignatureState
    /// True when created by calendar seeder (not user-proven). Enables immediate capitulation.
    public var isSeededBaseline: Bool

    public var id: String { semanticHash }

    /// Mean confidence across TOD buckets.
    public var meanConfidence: Double { confidence.mean }

    public init(
        semanticHash: String,
        learnedConstraint: TimeConstraint = .flexible,
        overrideCount: Int = 0,
        confidence: TemporalConfidence = .neutral,
        lastUpdated: Date = Date(),
        createdAt: Date = Date(),
        lastSeenInSchedule: Date? = nil,
        state: SignatureState = .active,
        isSeededBaseline: Bool = false
    ) {
        self.semanticHash = semanticHash
        self.learnedConstraint = learnedConstraint
        self.overrideCount = overrideCount
        self.confidence = confidence
        self.lastUpdated = lastUpdated
        self.createdAt = createdAt
        self.lastSeenInSchedule = lastSeenInSchedule ?? lastUpdated
        self.state = state
        self.isSeededBaseline = isSeededBaseline
    }

    /// Factory default when no learning data exists.
    public static func factoryDefault(hash: String) -> BehavioralSignature {
        BehavioralSignature(
            semanticHash: hash,
            learnedConstraint: .flexible,
            overrideCount: 0,
            confidence: .neutral
        )
    }

    /// Seeded baselines start weak so one user override rewrites truth immediately.
    public static func seededBaseline(
        hash: String,
        constraint: TimeConstraint,
        now: Date = Date()
    ) -> BehavioralSignature {
        BehavioralSignature(
            semanticHash: hash,
            learnedConstraint: constraint,
            overrideCount: 0,
            confidence: .seededLow,
            lastUpdated: now,
            createdAt: now,
            lastSeenInSchedule: now,
            state: .active,
            isSeededBaseline: true
        )
    }

    // Backward-compatible decode: older vault JSON lacks state / isSeededBaseline.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        semanticHash = try c.decode(String.self, forKey: .semanticHash)
        learnedConstraint = try c.decode(TimeConstraint.self, forKey: .learnedConstraint)
        overrideCount = try c.decodeIfPresent(Int.self, forKey: .overrideCount) ?? 0
        confidence = try c.decodeIfPresent(TemporalConfidence.self, forKey: .confidence) ?? .neutral
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? lastUpdated
        lastSeenInSchedule = try c.decodeIfPresent(Date.self, forKey: .lastSeenInSchedule) ?? lastUpdated
        state = try c.decodeIfPresent(SignatureState.self, forKey: .state) ?? .active
        isSeededBaseline = try c.decodeIfPresent(Bool.self, forKey: .isSeededBaseline) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case semanticHash, learnedConstraint, overrideCount, confidence
        case lastUpdated, createdAt, lastSeenInSchedule, state, isSeededBaseline
    }
}

// MARK: - Vault envelope

public struct BehavioralVaultEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var signatures: [BehavioralSignature]
    public var updatedAt: Date

    public static let currentSchemaVersion = 1

    public static func empty(now: Date = Date()) -> BehavioralVaultEnvelope {
        BehavioralVaultEnvelope(schemaVersion: currentSchemaVersion, signatures: [], updatedAt: now)
    }

    public mutating func upsert(_ signature: BehavioralSignature, now: Date = Date()) {
        if let idx = signatures.firstIndex(where: { $0.semanticHash == signature.semanticHash }) {
            signatures[idx] = signature
        } else {
            signatures.append(signature)
        }
        updatedAt = now
    }

    public mutating func remove(hash: String, now: Date = Date()) {
        signatures.removeAll { $0.semanticHash == hash }
        updatedAt = now
    }

    public func signature(for hash: String) -> BehavioralSignature? {
        signatures.first { $0.semanticHash == hash }
    }
}

// MARK: - Amnesia protocol

/// Instantly forgets learned assumptions for a task class (factory reset for one hash).
public enum BehavioralAmnesia {
    @discardableResult
    public static func resetSignature(
        for hash: String,
        envelope: inout BehavioralVaultEnvelope,
        now: Date = Date()
    ) -> Bool {
        guard envelope.signature(for: hash) != nil else { return false }
        envelope.remove(hash: hash, now: now)
        return true
    }
}
