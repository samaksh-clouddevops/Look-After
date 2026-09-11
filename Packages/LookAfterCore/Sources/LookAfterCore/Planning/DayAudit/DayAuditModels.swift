import Foundation

// MARK: - Faults

/// A single day-supervisor finding (sense / time / energy).
public struct DayAuditFault: Identifiable, Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable {
        case low
        case medium
        case high
    }

    public enum SourceKind: String, Sendable, Equatable {
        case preWindowFit
        case proactive
        case overlap
        case capacity
        case parkedPull
        case yesterday
    }

    public let id: String
    public let severity: Severity
    public let message: String
    public let relatedTaskIDs: [String]
    public let sourceKind: SourceKind
    /// When true, Start my day should ask before applying related proposals.
    public let needsJudgment: Bool

    public init(
        id: String = UUID().uuidString,
        severity: Severity,
        message: String,
        relatedTaskIDs: [String] = [],
        sourceKind: SourceKind,
        needsJudgment: Bool = false
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.relatedTaskIDs = relatedTaskIDs
        self.sourceKind = sourceKind
        self.needsJudgment = needsJudgment
    }
}

// MARK: - Fixes & pulls

public enum DayAuditFixKind: String, Sendable, Equatable {
    case shrinkTask
    case skipTask
    case deferTask
    case pullParked
    case pullYesterday
}

public struct DayAuditFix: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: DayAuditFixKind
    public let taskID: String
    public let title: String
    public let detail: String
    /// Suggested duration when kind == .shrinkTask.
    public let suggestedMinutes: Int?

    public init(
        id: String = UUID().uuidString,
        kind: DayAuditFixKind,
        taskID: String,
        title: String,
        detail: String,
        suggestedMinutes: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.title = title
        self.detail = detail
        self.suggestedMinutes = suggestedMinutes
    }
}

public struct DayAuditPullCandidate: Identifiable, Sendable, Equatable {
    public enum Origin: String, Sendable, Equatable {
        case parked
        case yesterday
        case fluid
    }

    public let id: String
    public let taskID: String
    public let title: String
    public let origin: Origin
    public let estimatedMinutes: Int
    public let score: Double

    public init(
        id: String = UUID().uuidString,
        taskID: String,
        title: String,
        origin: Origin,
        estimatedMinutes: Int,
        score: Double = 0
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.origin = origin
        self.estimatedMinutes = estimatedMinutes
        self.score = score
    }
}

public struct DayAuditQuestion: Identifiable, Sendable, Equatable {
    public let id: String
    public let prompt: String
    public let options: [String]
    public let relatedFaultID: String?
    public let relatedTaskIDs: [String]

    public init(
        id: String = UUID().uuidString,
        prompt: String,
        options: [String],
        relatedFaultID: String? = nil,
        relatedTaskIDs: [String] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.relatedFaultID = relatedFaultID
        self.relatedTaskIDs = relatedTaskIDs
    }
}

public struct DayAuditCapacitySummary: Sendable, Equatable {
    public let bandLabel: String
    public let energyPercent: Int
    public let bookedFlexMinutes: Int
    public let remainingFlexMinutes: Int
    public let isOverloaded: Bool

    public init(
        bandLabel: String,
        energyPercent: Int,
        bookedFlexMinutes: Int,
        remainingFlexMinutes: Int,
        isOverloaded: Bool
    ) {
        self.bandLabel = bandLabel
        self.energyPercent = energyPercent
        self.bookedFlexMinutes = bookedFlexMinutes
        self.remainingFlexMinutes = remainingFlexMinutes
        self.isOverloaded = isOverloaded
    }

    public var line: String {
        if isOverloaded {
            return "\(bandLabel) · \(bookedFlexMinutes)m booked flex — overloaded vs energy."
        }
        return "\(bandLabel) · \(remainingFlexMinutes)m flex still open."
    }
}

/// Full morning / Start-my-day supervisor snapshot.
public struct DayAuditResult: Sendable, Equatable {
    public let faults: [DayAuditFault]
    public let possiblePulls: [DayAuditPullCandidate]
    public let notPossible: [DayAuditPullCandidate]
    public let capacitySummary: DayAuditCapacitySummary
    public let clarifyingQuestions: [DayAuditQuestion]
    /// Applied only after user accepts the check (or taps the related chip).
    public let proposedFixes: [DayAuditFix]
    /// Reserved for physics-safe no-ops; Phase 1 keeps this empty (cascade owns overlaps).
    public let safeAutoFixes: [DayAuditFix]
    public let generatedAt: Date

    public init(
        faults: [DayAuditFault] = [],
        possiblePulls: [DayAuditPullCandidate] = [],
        notPossible: [DayAuditPullCandidate] = [],
        capacitySummary: DayAuditCapacitySummary,
        clarifyingQuestions: [DayAuditQuestion] = [],
        proposedFixes: [DayAuditFix] = [],
        safeAutoFixes: [DayAuditFix] = [],
        generatedAt: Date = Date()
    ) {
        self.faults = faults
        self.possiblePulls = possiblePulls
        self.notPossible = notPossible
        self.capacitySummary = capacitySummary
        self.clarifyingQuestions = clarifyingQuestions
        self.proposedFixes = proposedFixes
        self.safeAutoFixes = safeAutoFixes
        self.generatedAt = generatedAt
    }

    public var hasBlockingQuestions: Bool {
        !clarifyingQuestions.isEmpty
    }

    public var hasMaterialFindings: Bool {
        !faults.isEmpty || !proposedFixes.isEmpty || !possiblePulls.isEmpty || capacitySummary.isOverloaded
    }

    /// Hero / narrative lines derived from audit (deterministic).
    public var summaryLines: [String] {
        var lines: [String] = [capacitySummary.line]
        let topFaults = faults.prefix(2).map(\.message)
        lines.append(contentsOf: topFaults)
        if let pull = possiblePulls.first {
            lines.append("Could pull “\(pull.title)” from \(pull.origin.rawValue).")
        }
        if clarifyingQuestions.isEmpty == false {
            lines.append("One check before you start.")
        }
        return Array(lines.prefix(4))
    }
}
