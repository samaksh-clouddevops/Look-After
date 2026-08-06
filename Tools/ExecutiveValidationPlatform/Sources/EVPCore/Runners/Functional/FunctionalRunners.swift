import Foundation

public struct BuildValidator: Sendable {
    private let packages = [
        "LookAfterCore",
        "ExecutiveBrain",
        "LookAfterData",
        "LookAfterFeatures",
        "LookAfterAI",
        "LookAfterHealth"
    ]

    public init() {}

    public func run(repoRoot: String = EVPPaths.repoRoot) async throws -> [TestResult] {
        var results: [TestResult] = []
        let logsDir = EVPPaths.engineArtifact("logs")
        try? FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)

        for pkg in packages {
            let start = Date()
            let pkgPath = (repoRoot as NSString).appendingPathComponent("Packages/\(pkg)")
            let logPath = (logsDir as NSString).appendingPathComponent("swift-test-\(pkg).log")
            let (status, evidence) = await runSwiftTest(at: pkgPath, logPath: logPath)
            results.append(TestResult(
                requirementId: "BUILD-\(pkg)",
                sourceDocument: "Documentation/qa/11-regression-suite.md",
                validationLayer: .functional,
                status: status,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                evidence: evidence,
                message: status == .pass ? nil : "swift test failed for \(pkg) — see \(logPath)"
            ))
        }
        return results
    }

    private func runSwiftTest(at path: String, logPath: String) async -> (TestStatus, [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "test", "--package-path", path]
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            try? output.write(toFile: logPath, atomically: true, encoding: .utf8)
            let lines = output.split(separator: "\n").suffix(20).map(String.init)
            if process.terminationStatus == 0 {
                return (.pass, lines + ["log: \(logPath)"])
            }
            return (.fail, lines + ["exit: \(process.terminationStatus)", "log: \(logPath)"])
        } catch {
            let message = error.localizedDescription
            try? message.write(toFile: logPath, atomically: true, encoding: .utf8)
            return (.error, [message, "log: \(logPath)"])
        }
    }
}

public struct StaticAnalysisEngine: Sendable {
    public init() {}

    public func run(qaRoot: String = EVPPaths.qaRoot) throws -> [TestResult] {
        let parser = QASpecParser()
        let requirements = try parser.parseAllDocuments(qaRoot: qaRoot)
        let docCount = Set(requirements.map(\.sourceDocument)).count
        let status: TestStatus = requirements.count >= 50 ? .pass : .fail
        return [TestResult(
            requirementId: "STATIC-RTM",
            sourceDocument: "Documentation/qa/README.md",
            validationLayer: .staticValidation,
            status: status,
            evidence: [
                "requirementsIndexed: \(requirements.count)",
                "sourceDocuments: \(docCount)"
            ],
            message: status == .pass ? nil : "Expected ≥50 indexed requirements"
        )]
    }
}

public struct FunctionalTestRunner: Sendable {
    public init() {}

    public func run(tier: Int = 2) async throws -> [TestResult] {
        var results = try StaticAnalysisEngine().run()
        if tier >= 2 {
            results.append(contentsOf: try await BuildValidator().run())
        }
        return results
    }
}

public struct PerformanceSpecLoader: Sendable {
    public init() {}

    public func run() throws -> [TestResult] {
        let path = EVPPaths.qaDoc("09-performance-benchmarks.md")
        let exists = FileManager.default.fileExists(atPath: path)
        return [TestResult(
            requirementId: "PERF-SPEC-LOAD",
            sourceDocument: "Documentation/qa/09-performance-benchmarks.md",
            validationLayer: .functional,
            status: exists ? .pass : .fail,
            evidence: exists ? ["Spec loaded"] : ["Missing spec file"]
        )]
    }
}
