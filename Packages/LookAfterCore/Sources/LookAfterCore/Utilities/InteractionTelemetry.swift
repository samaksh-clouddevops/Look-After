import Foundation
import os

/// Records manual timeline constraint overrides for Executive Brain learning.
public protocol InteractionTelemetryServing: Sendable {
    func recordConstraintChange(
        taskID: String,
        from: TimeConstraint,
        to: TimeConstraint,
        source: ConstraintChangeSource
    )

    /// Optional rich path — semantic hash + title for vault learning.
    func recordConstraintChange(
        taskID: String,
        taskTitle: String,
        semanticType: String?,
        from: TimeConstraint,
        to: TimeConstraint,
        source: ConstraintChangeSource
    )
}

public extension InteractionTelemetryServing {
    func recordConstraintChange(
        taskID: String,
        taskTitle: String,
        semanticType: String?,
        from: TimeConstraint,
        to: TimeConstraint,
        source: ConstraintChangeSource
    ) {
        recordConstraintChange(taskID: taskID, from: from, to: to, source: source)
    }
}

public enum ConstraintChangeSource: String, Codable, Sendable, Equatable, CaseIterable {
    case swipe
    case accessibility
    case system
    /// User deleted/broke a Brain-locked recovery block after Sabotage Auction.
    case sabotageOverride
}

/// Default path: OSLog + append-only shadow log. Never mutates Behavioral Vault in real time.
public struct InteractionTelemetryService: InteractionTelemetryServing, Sendable {
    public static let shared = InteractionTelemetryService()

    private let logger = Logger(subsystem: "com.lookafter.app", category: "Interaction")
    private let logSink: any ConstraintTelemetryLogging

    public init(logSink: any ConstraintTelemetryLogging = InteractionTelemetryLogger.shared) {
        self.logSink = logSink
    }

    public func recordConstraintChange(
        taskID: String,
        from: TimeConstraint,
        to: TimeConstraint,
        source: ConstraintChangeSource
    ) {
        recordConstraintChange(
            taskID: taskID,
            taskTitle: "",
            semanticType: nil,
            from: from,
            to: to,
            source: source
        )
    }

    public func recordConstraintChange(
        taskID: String,
        taskTitle: String,
        semanticType: String?,
        from: TimeConstraint,
        to: TimeConstraint,
        source: ConstraintChangeSource
    ) {
        let direction: String
        if to == from.hardened(), to != from {
            direction = "hardened"
        } else if to == from.softened(), to != from {
            direction = "softened"
        } else {
            direction = "set"
        }
        let hash = BehavioralSemanticHash.make(
            taskID: taskID,
            title: taskTitle,
            semanticType: semanticType
        )
        logger.info(
            "Constraint \(direction, privacy: .public) to \(to.rawValue, privacy: .public) task=\(taskID, privacy: .public) hash=\(hash, privacy: .public) source=\(source.rawValue, privacy: .public)"
        )
        // Shadow append only — synthesis happens in BGProcessingTask.
        logSink.append(
            ConstraintTelemetryEvent(
                semanticHash: hash,
                taskID: taskID,
                originalConstraint: from,
                newConstraint: to,
                source: source
            )
        )
    }
}

/// In-memory spy for unit tests.
public final class InteractionTelemetrySpy: InteractionTelemetryServing, @unchecked Sendable {
    public struct Event: Equatable, Sendable {
        public let taskID: String
        public let taskTitle: String
        public let semanticHash: String
        public let from: TimeConstraint
        public let to: TimeConstraint
        public let source: ConstraintChangeSource
    }

    public private(set) var events: [Event] = []

    public init() {}

    public func recordConstraintChange(
        taskID: String,
        from: TimeConstraint,
        to: TimeConstraint,
        source: ConstraintChangeSource
    ) {
        recordConstraintChange(
            taskID: taskID,
            taskTitle: "",
            semanticType: nil,
            from: from,
            to: to,
            source: source
        )
    }

    public func recordConstraintChange(
        taskID: String,
        taskTitle: String,
        semanticType: String?,
        from: TimeConstraint,
        to: TimeConstraint,
        source: ConstraintChangeSource
    ) {
        let hash = BehavioralSemanticHash.make(
            taskID: taskID,
            title: taskTitle,
            semanticType: semanticType
        )
        events.append(
            Event(
                taskID: taskID,
                taskTitle: taskTitle,
                semanticHash: hash,
                from: from,
                to: to,
                source: source
            )
        )
    }

    public func reset() {
        events.removeAll()
    }
}
