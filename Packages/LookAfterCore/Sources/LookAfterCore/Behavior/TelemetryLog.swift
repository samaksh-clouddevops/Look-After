import Foundation

// MARK: - Append-only event

/// Shadow telemetry for constraint mutations. Never written into operational task rows.
public struct ConstraintTelemetryEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var semanticHash: String
    public var taskID: String
    public var originalConstraint: TimeConstraint
    public var newConstraint: TimeConstraint
    public var source: ConstraintChangeSource
    public var timestamp: Date
    public var timeOfDay: BehavioralTimeOfDay

    public init(
        id: String = UUID().uuidString,
        semanticHash: String,
        taskID: String,
        originalConstraint: TimeConstraint,
        newConstraint: TimeConstraint,
        source: ConstraintChangeSource,
        timestamp: Date = Date(),
        timeOfDay: BehavioralTimeOfDay? = nil
    ) {
        self.id = id
        self.semanticHash = semanticHash
        self.taskID = taskID
        self.originalConstraint = originalConstraint
        self.newConstraint = newConstraint
        self.source = source
        self.timestamp = timestamp
        self.timeOfDay = timeOfDay ?? BehavioralTimeOfDay.from(date: timestamp)
    }

    public var isSoftening: Bool {
        newConstraint == originalConstraint.softened() && newConstraint != originalConstraint
    }

    public var isHardening: Bool {
        newConstraint == originalConstraint.hardened() && newConstraint != originalConstraint
    }
}

// MARK: - Log envelope

public struct TelemetryLogEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var dayKey: String
    public var events: [ConstraintTelemetryEvent]
    public var updatedAt: Date

    public static let currentSchemaVersion = 2
    public static let filePrefix = "telemetry_"

    public static func empty(dayKey: String = "", now: Date = Date()) -> TelemetryLogEnvelope {
        TelemetryLogEnvelope(
            schemaVersion: currentSchemaVersion,
            dayKey: dayKey,
            events: [],
            updatedAt: now
        )
    }

    public mutating func append(_ event: ConstraintTelemetryEvent, now: Date = Date()) {
        events.append(event)
        updatedAt = now
    }

    /// Backward-compatible decode of v1 logs (no dayKey).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? ""
        events = try c.decodeIfPresent([ConstraintTelemetryEvent].self, forKey: .events) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, dayKey, events, updatedAt
    }

    public init(schemaVersion: Int, dayKey: String, events: [ConstraintTelemetryEvent], updatedAt: Date) {
        self.schemaVersion = schemaVersion
        self.dayKey = dayKey
        self.events = events
        self.updatedAt = updatedAt
    }
}

// MARK: - Day rotation helpers

public enum TelemetryLogRotation {
    public static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d_%02d_%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public static func fileName(dayKey: String) -> String {
        "\(TelemetryLogEnvelope.filePrefix)\(dayKey).json"
    }

    public static func isTelemetryFileName(_ name: String) -> Bool {
        name.hasPrefix(TelemetryLogEnvelope.filePrefix) && name.hasSuffix(".json")
    }

    public static func dayKey(fromFileName name: String) -> String? {
        guard isTelemetryFileName(name) else { return nil }
        return String(name.dropFirst(TelemetryLogEnvelope.filePrefix.count).dropLast(5))
    }
}

// MARK: - Logger protocol

/// Fast append path for the UI layer. Does **not** mutate BehavioralSignature.
public protocol ConstraintTelemetryLogging: Sendable {
    func append(_ event: ConstraintTelemetryEvent)
    /// Active writer buffer (today).
    func snapshot() -> TelemetryLogEnvelope
    /// Sealed prior-day logs for synthesis (excludes today's open file).
    func sealedLogs(excludingDayKey: String?) -> [(dayKey: String, envelope: TelemetryLogEnvelope)]
    func deleteSealedLogs(dayKeys: [String])
    func replaceAll(_ envelope: TelemetryLogEnvelope)
}
