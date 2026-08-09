import Foundation

/// Single entry for executive recommendations (ADR-007 / Phase 3 WP 3.1).
///
/// Concrete backends (ExecutiveBrain, FlowDirector, LLM) live in higher packages
/// and are injected when `ArchitectureFeatureFlags.useBrainFacade` is enabled.
public protocol BrainFacadeProtocol: Sendable {
    func recommend(_ input: BrainFacadeInput) async -> BrainFacadeOutput?
}

public struct BrainFacadeInput: Sendable, Equatable {
    public var userId: String
    public var userName: String
    public var now: Date
    public var sleepHours: Double?
    public var energyScore: Double?
    public var activeTaskCount: Int
    /// Opaque bag for backend-specific context (serialized by adapters).
    public var notes: String

    public init(
        userId: String,
        userName: String = "",
        now: Date = Date(),
        sleepHours: Double? = nil,
        energyScore: Double? = nil,
        activeTaskCount: Int = 0,
        notes: String = ""
    ) {
        self.userId = userId
        self.userName = userName
        self.now = now
        self.sleepHours = sleepHours
        self.energyScore = energyScore
        self.activeTaskCount = activeTaskCount
        self.notes = notes
    }
}

public struct BrainFacadeOutput: Sendable, Equatable {
    public var headline: String
    public var supportingLine: String
    public var taskID: String?
    public var backendID: String
    public var confidence: Double

    public init(
        headline: String,
        supportingLine: String = "",
        taskID: String? = nil,
        backendID: String,
        confidence: Double = 0.5
    ) {
        self.headline = headline
        self.supportingLine = supportingLine
        self.taskID = taskID
        self.backendID = backendID
        self.confidence = confidence
    }
}

/// Safe offline default — recovery-minded when sleep is short (Brain #12 alignment).
public struct DeterministicBrainFacadeBackend: BrainFacadeProtocol {
    public init() {}

    public func recommend(_ input: BrainFacadeInput) async -> BrainFacadeOutput? {
        if let sleep = input.sleepHours, sleep < 6 {
            return BrainFacadeOutput(
                headline: "Protect capacity before deep work",
                supportingLine: "Sleep was short — start with a light recovery block.",
                taskID: nil,
                backendID: "deterministic.recovery",
                confidence: 0.8
            )
        }
        if input.activeTaskCount == 0 {
            return BrainFacadeOutput(
                headline: "Capture what's on your mind",
                supportingLine: "Empty board — a quick inbox dump reduces cognitive load.",
                backendID: "deterministic.capture",
                confidence: 0.55
            )
        }
        return BrainFacadeOutput(
            headline: "Continue your next active task",
            supportingLine: "\(input.activeTaskCount) open — pick the smallest start.",
            backendID: "deterministic.next",
            confidence: 0.5
        )
    }
}

/// Router that can stack backends later; for now prefers deterministic always.
public struct BrainFacadeRouter: BrainFacadeProtocol {
    private let primary: any BrainFacadeProtocol
    private let fallback: any BrainFacadeProtocol

    public init(
        primary: any BrainFacadeProtocol = DeterministicBrainFacadeBackend(),
        fallback: any BrainFacadeProtocol = DeterministicBrainFacadeBackend()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func recommend(_ input: BrainFacadeInput) async -> BrainFacadeOutput? {
        if let out = await primary.recommend(input) {
            return out
        }
        return await fallback.recommend(input)
    }
}
