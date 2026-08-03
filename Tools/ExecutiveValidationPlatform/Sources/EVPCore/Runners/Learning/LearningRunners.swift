import Foundation
import ExecutiveBrain

public struct LearningSimulationRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "LearningSimulationRunner",
            layer: .learning,
            sourceDocument: "Documentation/qa/16-learning-validation.md",
            requirementPrefix: "LO-LEARN-"
        ).run(options: options)
    }
}

public struct MemoryDriftRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "MemoryDriftRunner",
            layer: .learning,
            sourceDocument: "Documentation/qa/31-memory-drift-validation.md",
            requirementPrefix: "MEM-"
        ).run(options: options)
    }
}

public struct ExecutiveCostAuditor: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let regression = DecisionRegressionRunner()
        let decisions = try regression.run()
        var burdens: [[String: Any]] = []

        for result in decisions where result.status == .pass || result.status == .fail {
            if let burdenLine = result.evidence.first(where: { $0.contains("totalBurden") }) {
                burdens.append(["id": result.requirementId, "note": burdenLine])
            }
        }

        let outputPath = EVPPaths.engineArtifact("cost-history.json")
        try FileManager.default.createDirectory(atPath: EVPPaths.engineOutput, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "decisions": decisions.count,
            "entries": burdens
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outputPath))

        return [TestResult(
            requirementId: "LO-COST-AUDIT",
            sourceDocument: "Documentation/qa/19-executive-cost-validation.md",
            validationLayer: .executiveCost,
            status: .notImplemented,
            evidence: [
                "Phase 1: cost-history.json written",
                "path: \(outputPath)",
                "decisionFixturesRun: \(decisions.count)"
            ]
        )]
    }
}

public struct CounterfactualEngine: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let fixturePath = EVPPaths.fixture("counterfactual/cf_001.json")
        guard FileManager.default.fileExists(atPath: fixturePath) else {
            return try await ScaffoldRunner(
                name: "CounterfactualEngine",
                layer: .executiveCost,
                sourceDocument: "Documentation/qa/28-counterfactual-engine.md",
                requirementPrefix: "CF-"
            ).run(options: options)
        }

        let builder = BrainFixtureBuilder()
        let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        struct CFFixture: Codable { var id: String; var input: FixtureInput; var expected: CFExpected }
        struct CFExpected: Codable { var minSimulations: Int }
        let fixture = try JSONDecoder().decode(CFFixture.self, from: data)
        let input = builder.buildInput(from: fixture.input)
        let state = ExecutiveBrainEngine().tick(input)
        let simCount = state.decision.simulations.count
        let passed = simCount >= fixture.expected.minSimulations

        return [TestResult(
            requirementId: fixture.id,
            sourceDocument: "Documentation/qa/28-counterfactual-engine.md",
            validationLayer: .executiveCost,
            status: passed ? .pass : .fail,
            evidence: [
                "simulations: \(simCount)",
                "minRequired: \(fixture.expected.minSimulations)"
            ],
            message: passed ? nil : "Insufficient simulations generated"
        )]
    }
}

public struct AICostAuditor: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "AICostAuditor",
            layer: .executiveCost,
            sourceDocument: "Documentation/qa/35-ai-cost-validation.md",
            requirementPrefix: "AICOST-"
        ).run(options: options)
    }
}
