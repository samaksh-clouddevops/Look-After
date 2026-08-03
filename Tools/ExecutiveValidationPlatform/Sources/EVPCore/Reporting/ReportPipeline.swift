import Foundation

public struct ReportPipeline: Sendable {
    public init() {}

    public func writeAll(summary: EVPRunSummary, rtm: RTMIndex?, versionReport: VersionComparisonReport? = nil) throws {
        try FileManager.default.createDirectory(atPath: EVPPaths.engineOutput, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try encoder.encode(summary).write(to: URL(fileURLWithPath: EVPPaths.engineArtifact("results.json")))

        if let versionReport {
            try encoder.encode(versionReport).write(to: URL(fileURLWithPath: EVPPaths.engineArtifact("version-comparison.json")))
        }

        let md = renderMarkdown(summary: summary, rtm: rtm)
        try md.write(to: URL(fileURLWithPath: EVPPaths.engineArtifact("report.md")), atomically: true, encoding: .utf8)

        let html = renderHTML(summary: summary, rtm: rtm, versionReport: versionReport)
        try html.write(to: URL(fileURLWithPath: EVPPaths.engineArtifact("dashboard.html")), atomically: true, encoding: .utf8)

        let junit = renderJUnit(summary: summary)
        try junit.write(to: URL(fileURLWithPath: EVPPaths.engineArtifact("junit.xml")), atomically: true, encoding: .utf8)

        let gha = renderGHASummary(summary: summary, rtm: rtm, versionReport: versionReport)
        try gha.write(to: URL(fileURLWithPath: EVPPaths.engineArtifact("github-summary.md")), atomically: true, encoding: .utf8)
    }

    private func renderMarkdown(summary: EVPRunSummary, rtm: RTMIndex?) -> String {
        var md = "# EVP Report: \(summary.command)\n\n"
        md += "**Started:** \(summary.startedAt.formatted())\n"
        md += "**Finished:** \(summary.finishedAt.formatted())\n"
        md += "**Result:** \(summary.success ? "PASS" : "FAIL") (\(summary.passed) pass, \(summary.failed) fail, \(summary.skipped) skip)\n\n"

        if let rtm {
            md += "## Pyramid layers\n\n"
            for layer in ValidationLayer.allCases {
                md += "- **\(layer.rawValue)** \(layer.displayName): \(rtm.countsByLayer[layer.rawValue, default: 0]) requirements\n"
            }
            md += "\n"
        }

        md += "## Results\n\n| ID | Layer | Status | Duration | Source |\n"
        md += "|----|-------|--------|----------|--------|\n"
        for r in summary.results {
            md += "| \(r.requirementId) | \(r.validationLayer.rawValue) | \(r.status.rawValue) | \(r.durationMs)ms | \(r.sourceDocument) |\n"
        }
        return md
    }

    private func renderHTML(summary: EVPRunSummary, rtm: RTMIndex?, versionReport: VersionComparisonReport?) -> String {
        var layersHTML = ""
        if let rtm {
            for layer in ValidationLayer.allCases {
                let count = rtm.countsByLayer[layer.rawValue, default: 0]
                layersHTML += "<li><strong>\(layer.rawValue)</strong> \(layer.displayName): \(count)</li>"
            }
        }

        var rows = ""
        for r in summary.results {
            let cls = r.status == .pass ? "pass" : (r.status == .fail ? "fail" : "skip")
            rows += "<tr class=\"\(cls)\"><td>\(r.requirementId)</td><td>\(r.validationLayer.rawValue)</td><td>\(r.status.rawValue)</td><td>\(r.durationMs)ms</td><td>\(r.sourceDocument)</td></tr>"
        }

        var northStar = ""
        if let vr = versionReport {
            northStar = """
            <section><h2>North-star verdict</h2>
            <p><em>\(vr.question)</em></p>
            <p><strong>\(vr.verdict)</strong> — \(String(format: "%.1f", vr.evidence.betterOutcomesPct))% better outcomes (\(vr.evidence.decisionsEvaluated) decisions)</p>
            </section>
            """
        }

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>EVP Dashboard</title>
        <style>
        body{font-family:system-ui,sans-serif;margin:2rem;background:#0d1117;color:#e6edf3}
        .pass{color:#3fb950}.fail{color:#f85149}.skip{color:#8b949e}
        table{border-collapse:collapse;width:100%} th,td{border:1px solid #30363d;padding:8px;text-align:left}
        h1,h2{color:#58a6ff}
        </style></head><body>
        <h1>Executive Validation Platform</h1>
        <p>Command: <code>\(summary.command)</code> — \(summary.success ? "PASS" : "FAIL")</p>
        \(northStar)
        <section><h2>Validation Pyramid</h2><ul>\(layersHTML)</ul></section>
        <section><h2>Results (\(summary.results.count))</h2>
        <table><thead><tr><th>ID</th><th>Layer</th><th>Status</th><th>Duration</th><th>Source</th></tr></thead>
        <tbody>\(rows)</tbody></table></section>
        </body></html>
        """
    }

    private func renderJUnit(summary: EVPRunSummary) -> String {
        var cases = ""
        for r in summary.results where r.status != .notImplemented {
            cases += """
            <testcase name="\(r.requirementId)" classname="\(r.validationLayer.rawValue)" time="\(Double(r.durationMs)/1000.0)">
            \(r.status == .fail ? "<failure message=\"\(r.message ?? "failed")\"/>" : "")
            </testcase>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuite name="EVP" tests="\(summary.results.count)" failures="\(summary.failed)" time="\(summary.finishedAt.timeIntervalSince(summary.startedAt))">
        \(cases)
        </testsuite>
        """
    }

    private func renderGHASummary(summary: EVPRunSummary, rtm: RTMIndex?, versionReport: VersionComparisonReport?) -> String {
        var md = "## Executive Validation Platform\n\n"
        md += "| Metric | Value |\n|--------|-------|\n"
        md += "| Command | `\(summary.command)` |\n"
        md += "| Pass | \(summary.passed) |\n"
        md += "| Fail | \(summary.failed) |\n"
        md += "| Skip/Scaffold | \(summary.skipped) |\n"
        if let rtm {
            md += "| Requirements indexed | \(rtm.requirements.count) |\n"
        }
        if let vr = versionReport {
            md += "| North-star verdict | **\(vr.verdict)** |\n"
        }
        md += "\n### Layer status\n\n"
        for layer in ValidationLayer.allCases {
            let layerResults = summary.results.filter { $0.validationLayer == layer }
            let pass = layerResults.filter { $0.status == .pass }.count
            let fail = layerResults.filter { $0.status == .fail }.count
            if !layerResults.isEmpty {
                md += "- **\(layer.rawValue)**: \(pass) pass, \(fail) fail\n"
            }
        }
        return md
    }
}

public struct EVPOrchestrator: Sendable {
    public init() {}

    public func run(command: String, options: EVPRunOptions = EVPRunOptions()) async throws -> EVPRunSummary {
        let started = Date()
        var results: [TestResult] = []

        switch command {
        case "index":
            let index = try RequirementsRegistry().writeRTM()
            return makeSummary(
                command: command,
                started: started,
                results: [TestResult(
                    requirementId: "RTM-INDEX",
                    sourceDocument: "Documentation/qa/README.md",
                    validationLayer: .staticValidation,
                    status: index.requirements.count > 0 ? .pass : .fail,
                    evidence: ["requirementsIndexed: \(index.requirements.count)"]
                )]
            )

        case "run":
            if options.layer == .decision {
                results = try DecisionRegressionRunner().run()
            } else {
                let tier = options.tier ?? 2
                results = try await FunctionalTestRunner().run(tier: tier)
                results.append(contentsOf: try PerformanceSpecLoader().run())
            }

        case "decisions":
            results = try DecisionRegressionRunner().run()

        case "replay":
            results = try await RealityReplayRunner().run(options: options)

        case "simulate":
            results = try await LifeSimulatorRunner().run(options: options)

        case "counterfactual":
            results = try await CounterfactualEngine().run(options: options)

        case "calibrate":
            results = try await ConfidenceCalibrator().run(options: options)

        case "explain":
            results = try await ExplainabilityValidator().run(options: options)

        case "memory-drift":
            results = try await MemoryDriftRunner().run(options: options)

        case "cost-audit":
            results = try await ExecutiveCostAuditor().run(options: options)
            results.append(contentsOf: try await AICostAuditor().run(options: options))

        case "trust":
            results = try await TrustEvaluator().run(options: options)

        case "satisfaction":
            results = try await SatisfactionTracker().run(options: options)

        case "release":
            let prior = try await run(command: "decisions", options: options)
            let functional = try await FunctionalTestRunner().run(tier: 2)
            let combined = prior.results + functional
            let (verdict, items) = ReleaseChecklistEvaluator().evaluate(results: combined)
            results = items + [TestResult(
                requirementId: "RELEASE-VERDICT",
                sourceDocument: "Documentation/qa/12-release-checklist.md",
                validationLayer: .staticValidation,
                status: verdict == "Release Ready" ? .pass : .fail,
                evidence: ["verdict: \(verdict)"]
            )]

        case "readiness":
            let prior = try await run(command: "decisions", options: options)
            let rtm = try? RequirementsRegistry().buildIndex()
            let (score, _) = ProductionReadinessCalculator().calculate(results: prior.results, rtm: rtm)
            results = [TestResult(
                requirementId: "READINESS-SCORE",
                sourceDocument: "Documentation/qa/14-production-readiness.md",
                validationLayer: .staticValidation,
                status: score >= 85 ? .pass : .fail,
                evidence: ["score: \(String(format: "%.1f", score))/100"]
            )]

        case "compare-versions":
            let parts = options.requirementId?.split(separator: " ").map(String.init) ?? ["v1.0.0", "v1.1.0"]
            let v1 = parts.count > 0 ? parts[0] : "v1.0.0"
            let v2 = parts.count > 1 ? parts[1] : "v1.1.0"
            let decisionResults = try DecisionRegressionRunner().run()
            let replayResults = try await RealityReplayRunner().run(options: EVPRunOptions(fixture: "REPLAY-001"))
            let all = decisionResults + replayResults
            let report = VersionComparisonBuilder().build(results: all, versionA: v1, versionB: v2)
            results = [TestResult(
                requirementId: "COMPARE-VERSIONS",
                sourceDocument: "Documentation/qa/27-reality-replay.md",
                validationLayer: .realityReplay,
                status: report.verdict == "Ship" ? .pass : .fail,
                evidence: [
                    "verdict: \(report.verdict)",
                    "betterOutcomesPct: \(report.evidence.betterOutcomesPct)",
                    "decisionsEvaluated: \(report.evidence.decisionsEvaluated)"
                ]
            )]
            let summary = makeSummary(command: command, started: started, results: results)
            try ReportPipeline().writeAll(summary: summary, rtm: try? RequirementsRegistry().buildIndex(), versionReport: report)
            return summary

        case "trace":
            guard let id = options.requirementId else {
                throw EVPError.parse("trace requires requirement ID")
            }
            let trace = try RequirementsRegistry().trace(requirementId: id)
            print(trace)
            return makeSummary(command: command, started: started, results: [])

        default:
            throw EVPError.runner("Unknown command: \(command)")
        }

        let summary = makeSummary(command: command, started: started, results: results)
        try ReportPipeline().writeAll(summary: summary, rtm: try? RequirementsRegistry().buildIndex())
        return summary
    }

    private func makeSummary(command: String, started: Date, results: [TestResult]) -> EVPRunSummary {
        EVPRunSummary(
            command: command,
            startedAt: started,
            finishedAt: Date(),
            results: results,
            passed: results.filter { $0.status == .pass }.count,
            failed: results.filter { $0.status == .fail }.count,
            skipped: results.filter { $0.status == .notImplemented || $0.status == .skip }.count
        )
    }
}
