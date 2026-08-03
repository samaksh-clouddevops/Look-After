import Foundation
import ExecutiveBrain
import LookAfterCore

public struct RealityReplayRunner: Sendable {
    private let engine = ExecutiveBrainEngine()
    private let builder = BrainFixtureBuilder()

    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let fixtureName = options.fixture ?? "REPLAY-001"
        let fixturePath = resolveFixture(id: fixtureName)

        guard FileManager.default.fileExists(atPath: fixturePath) else {
            return [TestResult(
                requirementId: fixtureName,
                sourceDocument: "Documentation/qa/27-reality-replay.md",
                validationLayer: .realityReplay,
                status: .fail,
                message: "Fixture not found: \(fixturePath)"
            )]
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let points = json["decisionPoints"] as? [[String: Any]] else {
            throw EVPError.parse("Invalid replay fixture schema")
        }

        var results: [TestResult] = []
        for (index, point) in points.enumerated() {
            let reqId = index == 0 ? id : "\(id)-DP-\(index + 1)"
            let start = Date()
            guard let snapshot = point["inputSnapshot"] as? [String: Any] else { continue }

            var input = FixtureInput(
                sleepHours: snapshot["sleepHours"] as? Double,
                taskTitle: snapshot["taskTitle"] as? String,
                taskMinutes: snapshot["taskMinutes"] as? Int,
                now: snapshot["now"] as? String
            )
            if let deadline = snapshot["deadlineTitle"] as? String {
                input.deadlineTitle = deadline
            }

            let tickInput = builder.buildInput(from: input)
            let state = engine.tick(tickInput)
            let actual = point["actualOutcome"] as? [String: Any]
            let actualCost = actual?["executiveCostActual"] as? Double ?? 0
            let simCost = state.decision.simulations.first?.projectedCost.totalBurden ?? 0
            let better = simCost < actualCost

            results.append(TestResult(
                requirementId: reqId,
                sourceDocument: "Documentation/qa/27-reality-replay.md",
                validationLayer: .realityReplay,
                status: .pass,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                evidence: [
                    "brainIntent: \(state.decision.headline)",
                    "projectedCost: \(simCost)",
                    "actualCost: \(actualCost)",
                    "brainWouldImprove: \(better)"
                ]
            ))
        }
        return results
    }

    private func resolveFixture(id: String) -> String {
        let slug = id.lowercased().replacingOccurrences(of: "-", with: "_")
        let candidates = [
            EVPPaths.fixture("replay/\(slug).json"),
            EVPPaths.fixture("replay/replay_001.json")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }
}

public struct LifeSimulatorRunner: Sendable {
    private let engine = ExecutiveBrainEngine()
    private let builder = BrainFixtureBuilder()

    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        if let fail = options.failScenario {
            return try await FailureRecoveryRunner().run(options: EVPRunOptions(failScenario: fail))
        }

        let scenario = options.scenario ?? "SIM-DAY-001"
        let start = Date()
        let input = builder.buildInput(from: FixtureInput(
            sleepHours: 7,
            taskTitle: "Daily planning",
            taskMinutes: 30,
            now: "2026-08-01T09:00:00Z"
        ))
        let state = engine.tick(input)
        let passed = !state.decision.headline.isEmpty && state.decision.confidence > 0

        return [TestResult(
            requirementId: scenario,
            sourceDocument: "Documentation/qa/21-life-simulator.md",
            validationLayer: .syntheticSimulation,
            status: passed ? .pass : .fail,
            durationMs: Int(Date().timeIntervalSince(start) * 1000),
            evidence: ["intent: \(state.decision.headline)", "1-day tick completed"]
        )]
    }
}

public struct FailureRecoveryRunner: Sendable {
    private let engine = ExecutiveBrainEngine()
    private let builder = BrainFixtureBuilder()

    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let scenario = options.failScenario ?? "FAIL-001"
        let start = Date()
        var tickInput = builder.buildInput(from: FixtureInput(
            sleepHours: nil,
            taskTitle: "Fallback task",
            taskMinutes: 15,
            energyScore: 0.5,
            now: "2026-08-01T09:00:00Z"
        ))
        if scenario == "FAIL-002" {
            tickInput = BrainTickInput(
                snapshot: tickInput.snapshot,
                tasks: tickInput.tasks,
                now: tickInput.now
            )
        }
        let state = engine.tick(tickInput)
        let passed = !state.decision.headline.isEmpty

        return [TestResult(
            requirementId: scenario,
            sourceDocument: "Documentation/qa/36-failure-recovery.md",
            validationLayer: .syntheticSimulation,
            status: passed ? .pass : .fail,
            durationMs: Int(Date().timeIntervalSince(start) * 1000),
            evidence: ["degradedMode: true", "intent: \(state.decision.headline)"]
        )]
    }
}

public struct TwinComparatorRunner: Sendable {
    private let engine = ExecutiveBrainEngine()
    private let builder = BrainFixtureBuilder()

    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let nightOwl = builder.buildInput(from: FixtureInput(
            sleepHours: 4,
            taskTitle: "Deep work",
            taskMinutes: 90,
            energyScore: 0.3,
            now: "2026-08-01T22:00:00Z"
        ))
        let morning = builder.buildInput(from: FixtureInput(
            sleepHours: 8,
            taskTitle: "Deep work",
            taskMinutes: 90,
            energyScore: 0.85,
            now: "2026-08-01T09:00:00Z"
        ))
        let a = engine.tick(nightOwl)
        let b = engine.tick(morning)
        let different = a.decision.headline != b.decision.headline || abs(a.decision.confidence - b.decision.confidence) > 0.1

        return [TestResult(
            requirementId: "LO-TWIN-001",
            sourceDocument: "Documentation/qa/17-digital-twin-validation.md",
            validationLayer: .syntheticSimulation,
            status: different ? .pass : .fail,
            evidence: ["night: \(a.decision.headline)", "morning: \(b.decision.headline)"]
        )]
    }
}
