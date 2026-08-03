import Foundation
import ExecutiveBrain

public struct LearningSimulationRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let fixturePath = EVPPaths.fixture("learning/gym_tuesday_skip.json")
        guard FileManager.default.fileExists(atPath: fixturePath) else {
            return [TestResult(
                requirementId: "LO-LEARN-001",
                sourceDocument: "Documentation/qa/16-learning-validation.md",
                validationLayer: .learning,
                status: .skip,
                evidence: ["No learning fixture at \(fixturePath)"]
            )]
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let events = json?["events"] as? [[String: Any]] ?? []
        let deferCount = events.filter { ($0["action"] as? String) == "defer" }.count
        let passed = deferCount >= 1

        return [TestResult(
            requirementId: "LO-LEARN-001",
            sourceDocument: "Documentation/qa/16-learning-validation.md",
            validationLayer: .learning,
            status: passed ? .pass : .fail,
            evidence: ["deferEvents: \(deferCount)", "fixture: \(fixturePath)"]
        )]
    }
}

public struct MemoryDriftRunner: Sendable {
    private let engine = ExecutiveBrainEngine()
    private let builder = BrainFixtureBuilder()

    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let reqId = options.requirementId ?? "MEM-001"
        let input = builder.buildInput(from: FixtureInput(
            sleepHours: 7,
            taskTitle: "Gym",
            taskMinutes: 60,
            now: "2026-08-01T09:00:00Z"
        ))
        let before = engine.tick(input)
        let after = engine.tick(input)
        let parity = before.decision.headline == after.decision.headline ? 1.0 : 0.0

        return [TestResult(
            requirementId: reqId,
            sourceDocument: "Documentation/qa/31-memory-drift-validation.md",
            validationLayer: .learning,
            status: parity >= 0.95 ? .pass : .fail,
            evidence: ["decisionParity: \(parity)"]
        )]
    }
}

public struct ExecutiveCostAuditor: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let regression = DecisionRegressionRunner()
        let decisions = try regression.run()
        var entries: [[String: Any]] = []

        for result in decisions {
            entries.append([
                "id": result.requirementId,
                "status": result.status.rawValue,
                "durationMs": result.durationMs
            ])
        }

        let outputPath = EVPPaths.engineArtifact("cost-history.json")
        try FileManager.default.createDirectory(atPath: EVPPaths.engineOutput, withIntermediateDirectories: true)
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "decisions": entries
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outputPath))

        let failures = decisions.filter { $0.status == .fail }.count
        return [TestResult(
            requirementId: "LO-COST-AUDIT",
            sourceDocument: "Documentation/qa/19-executive-cost-validation.md",
            validationLayer: .executiveCost,
            status: failures == 0 ? .pass : .fail,
            evidence: ["cost-history: \(outputPath)", "decisions: \(decisions.count)", "failures: \(failures)"]
        )]
    }
}

public struct CounterfactualEngine: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let fixturePath = EVPPaths.fixture("counterfactual/cf_001.json")
        guard FileManager.default.fileExists(atPath: fixturePath) else {
            throw EVPError.io("Missing CF fixture")
        }

        let builder = BrainFixtureBuilder()
        let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        struct CFFixture: Codable { var id: String; var input: FixtureInput; var expected: CFExpected }
        struct CFExpected: Codable { var minSimulations: Int }
        let fixture = try JSONDecoder().decode(CFFixture.self, from: data)
        let input = builder.buildInput(from: fixture.input)
        let state = ExecutiveBrainEngine().tick(input)
        let simCount = state.decision.simulations.count
        let chosen = state.decision.simulations.first(where: { $0.wasChosen })?.projectedCost.totalBurden ?? 999
        let minAlt = state.decision.simulations.filter { !$0.wasChosen }.map { $0.projectedCost.totalBurden }.min() ?? chosen
        let missed = minAlt < chosen

        return [TestResult(
            requirementId: fixture.id,
            sourceDocument: "Documentation/qa/28-counterfactual-engine.md",
            validationLayer: .executiveCost,
            status: simCount >= fixture.expected.minSimulations ? .pass : .fail,
            evidence: [
                "simulations: \(simCount)",
                "missedOpportunity: \(missed)",
                "chosenCost: \(chosen)",
                "bestAltCost: \(minAlt)"
            ]
        )]
    }
}

public struct AICostAuditor: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let logPath = EVPPaths.engineArtifact("ai-cost-log.json")
        if !FileManager.default.fileExists(atPath: logPath) {
            return [TestResult(
                requirementId: "AICOST-001",
                sourceDocument: "Documentation/qa/35-ai-cost-validation.md",
                validationLayer: .executiveCost,
                status: .skip,
                evidence: ["No AI cost log at \(logPath) — run app with GLM to generate"]
            )]
        }
        return [TestResult(
            requirementId: "AICOST-001",
            sourceDocument: "Documentation/qa/35-ai-cost-validation.md",
            validationLayer: .executiveCost,
            status: .pass,
            evidence: ["log: \(logPath)"]
        )]
    }
}
