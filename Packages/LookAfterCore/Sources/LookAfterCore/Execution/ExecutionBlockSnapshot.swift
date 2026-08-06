import Foundation

/// Visual / behavioral mode for Live Activity and Focus surfaces.
public enum ExecutionSurfaceMode: String, Codable, Sendable, Hashable {
    /// High-contrast timer — immovable focus block.
    case anchored
    /// Preferred slot with confidence — active focus allowed.
    case flexible
    /// Soft ambient indicator — no countdown pressure.
    case recovery
    /// Minimal unstructured gap before the next commitment.
    case fluidGap
    /// Nothing to project (day ended / empty schedule).
    case idle

    public var displayName: String {
        switch self {
        case .anchored: return "Anchored Window"
        case .flexible: return "Flexible Focus"
        case .recovery: return "Recovery Window"
        case .fluidGap: return "Fluid Gap"
        case .idle: return "Idle"
        }
    }

    /// Whether a Live Activity should remain visible for this mode.
    public var projectsLiveActivity: Bool {
        self != .idle
    }

    /// Whether the Dynamic Island should show a strict countdown timer.
    public var showsStrictCountdown: Bool {
        switch self {
        case .anchored, .flexible:
            return true
        case .recovery, .fluidGap, .idle:
            return false
        }
    }
}

/// Immutable projection of the currently active execution block.
/// Produced by `ExecutionBlockResolver` — UI / ActivityKit only consume this.
public struct ExecutionBlockSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var taskID: String?
    public var taskTitle: String
    public var category: FocusTaskCategory
    public var surfaceMode: ExecutionSurfaceMode
    public var constraintType: TimeConstraint?
    public var windowStart: Date
    public var windowEnd: Date
    public var progressFraction: Double
    public var nextUpSummary: String
    public var confidence: Double
    public var generatedAt: Date

    public init(
        id: String = UUID().uuidString,
        taskID: String? = nil,
        taskTitle: String,
        category: FocusTaskCategory,
        surfaceMode: ExecutionSurfaceMode,
        constraintType: TimeConstraint? = nil,
        windowStart: Date,
        windowEnd: Date,
        progressFraction: Double,
        nextUpSummary: String = "",
        confidence: Double = 1.0,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.category = category
        self.surfaceMode = surfaceMode
        self.constraintType = constraintType
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.progressFraction = min(1, max(0, progressFraction))
        self.nextUpSummary = nextUpSummary
        self.confidence = min(1, max(0, confidence))
        self.generatedAt = generatedAt
    }

    public var remainingSeconds: TimeInterval {
        max(0, windowEnd.timeIntervalSince(generatedAt))
    }

    public var isFocusEligible: Bool {
        switch surfaceMode {
        case .anchored, .flexible:
            return true
        case .recovery, .fluidGap, .idle:
            return false
        }
    }

    /// Constraint label projected onto Live Activity content state.
    public var constraintLabel: String {
        switch surfaceMode {
        case .anchored: return "Anchored"
        case .flexible: return "Flexible"
        case .recovery: return "Recovery"
        case .fluidGap: return "Fluid"
        case .idle: return "Idle"
        }
    }

    public static let idle = ExecutionBlockSnapshot(
        id: "idle",
        taskTitle: "",
        category: .fluidGap,
        surfaceMode: .idle,
        windowStart: .distantPast,
        windowEnd: .distantPast,
        progressFraction: 0,
        nextUpSummary: "",
        confidence: 0
    )
}
