import Foundation

public struct TrustEvaluator: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "TrustEvaluator",
            layer: .trust,
            sourceDocument: "Documentation/qa/26-trust-validation.md",
            requirementPrefix: "TRUST-"
        ).run(options: options)
    }
}

public struct ConfidenceCalibrator: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "ConfidenceCalibrator",
            layer: .trust,
            sourceDocument: "Documentation/qa/29-confidence-calibration.md",
            requirementPrefix: "CAL-"
        ).run(options: options)
    }
}

public struct SatisfactionTracker: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let outputPath = EVPPaths.engineArtifact("satisfaction.json")
        try FileManager.default.createDirectory(atPath: EVPPaths.engineOutput, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "status": "awaiting_ingest",
            "acceptRate": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: outputPath))

        return try await ScaffoldRunner(
            name: "SatisfactionTracker",
            layer: .trust,
            sourceDocument: "Documentation/qa/34-human-satisfaction.md",
            requirementPrefix: "SAT-"
        ).run(options: options)
    }
}

public struct ExplainabilityValidator: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "ExplainabilityValidator",
            layer: .crossCutting,
            sourceDocument: "Documentation/qa/30-explainability-validation.md",
            requirementPrefix: "EXPL-"
        ).run(options: options)
    }
}

public struct GoalGraphValidator: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "GoalGraphValidator",
            layer: .crossCutting,
            sourceDocument: "Documentation/qa/25-goal-graph-validation.md",
            requirementPrefix: "GOAL-"
        ).run(options: options)
    }
}

public struct GoalStabilityValidator: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "GoalStabilityValidator",
            layer: .crossCutting,
            sourceDocument: "Documentation/qa/32-goal-stability.md",
            requirementPrefix: "GSTAB-"
        ).run(options: options)
    }
}

public struct AutonomyBudgetEnforcer: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "AutonomyBudgetEnforcer",
            layer: .crossCutting,
            sourceDocument: "Documentation/qa/33-autonomy-budget.md",
            requirementPrefix: "AUTO-LVL-"
        ).run(options: options)
    }
}

public struct AutonomousActionValidator: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "AutonomousActionValidator",
            layer: .crossCutting,
            sourceDocument: "Documentation/qa/24-autonomous-actions.md",
            requirementPrefix: "AUTO-"
        ).run(options: options)
    }
}

public struct UIIntelligenceRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "UIIntelligenceRunner",
            layer: .crossCutting,
            sourceDocument: "Documentation/qa/23-ui-intelligence.md",
            requirementPrefix: "UI-INT-"
        ).run(options: options)
    }
}

public struct AIFixtureRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "AIFixtureRunner",
            layer: .executiveCost,
            sourceDocument: "Documentation/qa/07-ai-validation.md",
            requirementPrefix: "LO-AI-"
        ).run(options: options)
    }
}
