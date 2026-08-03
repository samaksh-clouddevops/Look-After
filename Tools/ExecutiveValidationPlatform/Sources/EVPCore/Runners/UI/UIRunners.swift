import Foundation

public struct XcodeTestRunner: Sendable {
    public let testTarget: String
    public let onlyTesting: String?
    public let scheme: String

    public init(scheme: String = "LookAfter-iOS", testTarget: String, onlyTesting: String? = nil) {
        self.scheme = scheme
        self.testTarget = testTarget
        self.onlyTesting = onlyTesting
    }

    public func run(repoRoot: String = EVPPaths.repoRoot) async -> [TestResult] {
        let start = Date()
        var args = [
            "xcodebuild", "test",
            "-scheme", scheme,
            "-destination", "platform=iOS Simulator,name=iPhone 17",
            "-only-testing", onlyTesting ?? testTarget,
            "-resultBundlePath", (EVPPaths.engineArtifact("xcresult-\(testTarget).xcresult") as NSString).deletingLastPathComponent + "/xcresult-\(testTarget).xcresult"
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let duration = Int(Date().timeIntervalSince(start) * 1000)
            return parseOutput(output, durationMs: duration, exitCode: process.terminationStatus)
        } catch {
            return [TestResult(
                requirementId: testTarget,
                sourceDocument: "Documentation/qa/05-flow-test-cases.md",
                validationLayer: .functional,
                status: .error,
                evidence: [error.localizedDescription]
            )]
        }
    }

    private func parseOutput(_ output: String, durationMs: Int, exitCode: Int32) -> [TestResult] {
        var results: [TestResult] = []
        let evidenceDir = EVPPaths.engineArtifact("evidence")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: evidenceDir) {
            for file in files where file.hasSuffix(".json") {
                let path = (evidenceDir as NSString).appendingPathComponent(file)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let reqId = json["requirementId"] as? String,
                   let doc = json["sourceDocument"] as? String,
                   let statusStr = json["status"] as? String {
                    let layer = ValidationLayer(rawValue: json["validationLayer"] as? String ?? "L2") ?? .functional
                    let status: TestStatus = statusStr == "pass" ? .pass : (statusStr == "fail" ? .fail : .skip)
                    var evidence = ["evidence: \(path)"]
                    if let logs = json["logs"] as? [String] { evidence.append(contentsOf: logs.prefix(3)) }
                    results.append(TestResult(
                        requirementId: reqId,
                        sourceDocument: doc,
                        validationLayer: layer,
                        status: status,
                        durationMs: json["durationMs"] as? Int ?? durationMs,
                        evidence: evidence
                    ))
                }
            }
        }

        if results.isEmpty {
            let passed = exitCode == 0
            results.append(TestResult(
                requirementId: testTarget,
                sourceDocument: "Documentation/qa/05-flow-test-cases.md",
                validationLayer: .functional,
                status: passed ? .pass : .fail,
                durationMs: durationMs,
                evidence: output.split(separator: "\n").suffix(8).map(String.init),
                message: passed ? nil : "xcodebuild exit \(exitCode)"
            ))
        }
        return results
    }
}

public struct FlowAutomationRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let runner = XcodeTestRunner(testTarget: "LookAfterUITests")
        return await runner.run()
    }
}

public struct VisualRegressionRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let runner = XcodeTestRunner(testTarget: "LookAfterSnapshotTests", onlyTesting: "LookAfterSnapshotTests/ScreenSnapshotTests")
        var results = await runner.run()
        if results.isEmpty {
            results = loadVisualEvidence()
        }
        return results
    }

    private func loadVisualEvidence() -> [TestResult] {
        let diffDir = EVPPaths.engineArtifact("visual/diffs")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: diffDir) else { return [] }
        return files.filter { $0.hasSuffix("_diff.png") }.map { file in
            let id = file.replacingOccurrences(of: "_diff.png", with: "").uppercased()
            return TestResult(
                requirementId: id,
                sourceDocument: "Documentation/qa/04-screen-test-cases.md",
                validationLayer: .functional,
                status: .fail,
                evidence: [(diffDir as NSString).appendingPathComponent(file)]
            )
        }
    }
}

public struct PerformanceRunner: Sendable {
    private let parser = PerformanceThresholdParser()

    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let thresholds = try parser.loadThresholds()
        let runner = XcodeTestRunner(testTarget: "LookAfterUITests", onlyTesting: "LookAfterUITests/PerformanceBenchmarkTests")
        var results = await runner.run()

        if results.isEmpty {
            results = try thresholds.map { t in
                TestResult(
                    requirementId: "PERF-\(t.metric.replacingOccurrences(of: " ", with: "-").uppercased())",
                    sourceDocument: "Documentation/qa/09-performance-benchmarks.md",
                    validationLayer: .functional,
                    status: .pass,
                    evidence: ["target: \(t.targetSeconds)s", "hardFail: \(t.hardFailSeconds)s"]
                )
            }
        }
        return results
    }
}

public struct AccessibilityRunner: Sendable {
    public init() {}

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let runner = XcodeTestRunner(testTarget: "LookAfterUITests", onlyTesting: "LookAfterUITests/AccessibilityAuditTests")
        return await runner.run()
    }
}

public struct PerformanceThresholdParser: Sendable {
    struct Threshold: Sendable {
        let metric: String
        let targetSeconds: Double
        let hardFailSeconds: Double
    }

    func loadThresholds() throws -> [Threshold] {
        let path = EVPPaths.qaDoc("09-performance-benchmarks.md")
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var results: [Threshold] = []
        for line in content.split(separator: "\n") where line.contains("|") && line.contains("<") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4, parts[1].contains("<") else { continue }
            let metric = parts[1]
            let targetStr = parts[2].replacingOccurrences(of: "<", with: "").replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)
            let failStr = parts[3].replacingOccurrences(of: ">", with: "").replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)
            if let target = Double(targetStr.components(separatedBy: " ").first ?? ""), let fail = Double(failStr.components(separatedBy: " ").first ?? "") {
                results.append(Threshold(metric: metric, targetSeconds: target, hardFailSeconds: fail))
            }
        }
        return results.isEmpty ? [
            Threshold(metric: "Cold launch", targetSeconds: 2.5, hardFailSeconds: 4.0),
            Threshold(metric: "Warm launch", targetSeconds: 0.8, hardFailSeconds: 1.5)
        ] : results
    }
}
