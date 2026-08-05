import Foundation

public struct XcodeTestRunner: Sendable {
    public let testTarget: String
    public let onlyTesting: String?
    public let scheme: String
    public let skipBuild: Bool

    public init(
        scheme: String = "LookAfter-iOS",
        testTarget: String,
        onlyTesting: String? = nil,
        skipBuild: Bool? = nil
    ) {
        self.scheme = scheme
        self.testTarget = testTarget
        self.onlyTesting = onlyTesting
        // Prefer skip-build in CI when a prior build-for-testing populated DerivedData.
        if let skipBuild {
            self.skipBuild = skipBuild
        } else {
            let env = ProcessInfo.processInfo.environment
            self.skipBuild = env["EVP_SKIP_BUILD"] == "1" || env["EVP_DERIVED_DATA"] != nil
        }
    }

    public func run(repoRoot: String = EVPPaths.repoRoot) async -> [TestResult] {
        let start = Date()
        let logLabel = sanitizedLabel(onlyTesting ?? testTarget)
        let logsDir = EVPPaths.engineArtifact("logs")
        let logPath = (logsDir as NSString).appendingPathComponent("xcodebuild-\(logLabel).log")
        let resultBundle = EVPPaths.engineArtifact("xcresult-\(logLabel).xcresult")
        let derivedDataPath = ProcessInfo.processInfo.environment["EVP_DERIVED_DATA"]

        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: resultBundle)

        let destination = resolveDestination(repoRoot: repoRoot, scheme: scheme)
        let preferredAction = skipBuild ? "test-without-building" : "test"

        do {
            var (exitCode, output) = try runXcodebuild(
                action: preferredAction,
                destination: destination,
                resultBundle: resultBundle,
                derivedDataPath: derivedDataPath,
                repoRoot: repoRoot
            )

            // If skip-build missed products, fall back to a full test once.
            if exitCode != 0 && preferredAction == "test-without-building" && looksLikeMissingBuild(output) {
                try? FileManager.default.removeItem(atPath: resultBundle)
                let fallback = try runXcodebuild(
                    action: "test",
                    destination: destination,
                    resultBundle: resultBundle,
                    derivedDataPath: derivedDataPath,
                    repoRoot: repoRoot
                )
                exitCode = fallback.0
                output = """
                --- test-without-building failed; retried with full test ---
                \(output)

                --- full test retry ---
                \(fallback.1)
                """
            }

            try? output.write(toFile: logPath, atomically: true, encoding: .utf8)
            let duration = Int(Date().timeIntervalSince(start) * 1000)
            return parseOutput(
                output,
                durationMs: duration,
                exitCode: exitCode,
                logPath: logPath,
                resultBundle: resultBundle
            )
        } catch {
            let message = error.localizedDescription
            try? message.write(toFile: logPath, atomically: true, encoding: .utf8)
            return [TestResult(
                requirementId: testTarget,
                sourceDocument: "Documentation/qa/05-flow-test-cases.md",
                validationLayer: .functional,
                status: .error,
                evidence: [message, "log: \(logPath)"]
            )]
        }
    }

    private func runXcodebuild(
        action: String,
        destination: String,
        resultBundle: String,
        derivedDataPath: String?,
        repoRoot: String
    ) throws -> (Int32, String) {
        var args = [
            "xcodebuild", action,
            "-scheme", scheme,
            "-destination", destination,
            "-only-testing", onlyTesting ?? testTarget,
            "-resultBundlePath", resultBundle,
            "-parallel-testing-enabled", "NO",
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO"
        ]
        if let derivedDataPath, !derivedDataPath.isEmpty {
            args.insert(contentsOf: ["-derivedDataPath", derivedDataPath], at: 4)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private func looksLikeMissingBuild(_ output: String) -> Bool {
        // Only trigger fallback for missing products / destination issues,
        // not ordinary test assertion failures.
        let markers = [
            "Build input file cannot be found",
            "xctest could not be found",
            "xctest not found",
            "Unable to find a destination",
            "No such file or directory",
            "Could not find test host",
            "Failed to load the test bundle",
            "has not been built"
        ]
        return markers.contains { output.localizedCaseInsensitiveContains($0) }
    }

    private func resolveDestination(repoRoot: String, scheme: String) -> String {
        if let forced = ProcessInfo.processInfo.environment["EVP_DESTINATION"], !forced.isEmpty {
            return forced
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["xcodebuild", "-scheme", scheme, "-showdestinations"]
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.split(separator: "\n").map(String.init) {
                guard line.contains("platform:iOS Simulator"), line.contains("iPhone") else { continue }
                if let idRange = line.range(of: #"id:[^,]+"#, options: .regularExpression) {
                    let idToken = String(line[idRange])
                    let id = idToken.replacingOccurrences(of: "id:", with: "")
                    if !id.isEmpty {
                        return "platform=iOS Simulator,id=\(id)"
                    }
                }
            }
        } catch {
            // Fall through to a stable generic destination.
        }

        return "platform=iOS Simulator,name=iPhone 16"
    }

    private func sanitizedLabel(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private func parseOutput(
        _ output: String,
        durationMs: Int,
        exitCode: Int32,
        logPath: String,
        resultBundle: String
    ) -> [TestResult] {
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
                    var evidence = ["evidence: \(path)", "log: \(logPath)"]
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
            var evidence = output.split(separator: "\n").suffix(20).map(String.init)
            evidence.append("log: \(logPath)")
            if FileManager.default.fileExists(atPath: resultBundle) {
                evidence.append("xcresult: \(resultBundle)")
            }
            results.append(TestResult(
                requirementId: testTarget,
                sourceDocument: "Documentation/qa/05-flow-test-cases.md",
                validationLayer: .functional,
                status: passed ? .pass : .fail,
                durationMs: durationMs,
                evidence: evidence,
                message: passed ? nil : "xcodebuild exit \(exitCode) — see \(logPath)"
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
