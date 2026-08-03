import Foundation

public struct RealityReplayRunner: Sendable {
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
            let reqId = "\(id)-DP-\(index + 1)"
            results.append(TestResult(
                requirementId: reqId,
                sourceDocument: "Documentation/qa/27-reality-replay.md",
                validationLayer: .realityReplay,
                status: .notImplemented,
                evidence: [
                    "Phase 1: schema validated",
                    "decisionPoint: \(index + 1)/\(points.count)",
                    "timestamp: \(point["timestamp"] as? String ?? "unknown")",
                    options.compareVersions.map { "compare: \($0.0) vs \($0.1)" } ?? "compare: pending Phase 2"
                ].compactMap { $0 }
            ))
        }

        results.insert(TestResult(
            requirementId: id,
            sourceDocument: "Documentation/qa/27-reality-replay.md",
            validationLayer: .realityReplay,
            status: .pass,
            evidence: [
                "fixture: \(fixturePath)",
                "decisionPoints: \(points.count)",
                "schema: valid"
            ]
        ), at: 0)

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
    private let scaffold: ScaffoldRunner

    public init() {
        scaffold = ScaffoldRunner(
            name: "LifeSimulatorRunner",
            layer: .syntheticSimulation,
            sourceDocument: "Documentation/qa/21-life-simulator.md",
            requirementPrefix: "SIM-"
        )
    }

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        if let fail = options.failScenario {
            return try await FailureRecoveryRunner().run(options: EVPRunOptions(failScenario: fail))
        }
        var opts = options
        if opts.scenario == nil { opts.scenario = "SIM-001" }
        return try await scaffold.run(options: opts)
    }
}

public struct FailureRecoveryRunner: Sendable {
    private let scaffold: ScaffoldRunner

    public init() {
        scaffold = ScaffoldRunner(
            name: "FailureRecoveryRunner",
            layer: .syntheticSimulation,
            sourceDocument: "Documentation/qa/36-failure-recovery.md",
            requirementPrefix: "FAIL-"
        )
    }

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await scaffold.run(options: options)
    }
}

public struct TwinComparatorRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        try await ScaffoldRunner(
            name: "TwinComparatorRunner",
            layer: .syntheticSimulation,
            sourceDocument: "Documentation/qa/17-digital-twin-validation.md",
            requirementPrefix: "LO-TWIN-"
        ).run(options: options)
    }
}
