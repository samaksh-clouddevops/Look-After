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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let resultsJSON = (try? encoder.encode(summary.results)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let qualityScore = summary.results.first { $0.requirementId == "QUALITY-SCORE" }?.evidence.first ?? "pending"
        let a11yScore = summary.results.flatMap { $0.evidence }.first { $0.contains("wcagComplianceScore") } ?? "N/A"

        let diffDir = EVPPaths.engineArtifact("visual/diffs")
        var diffGallery = ""
        if let files = try? FileManager.default.contentsOfDirectory(atPath: diffDir) {
            for file in files.filter({ $0.hasSuffix("_diff.png") }).sorted() {
                let rel = "visual/diffs/\(file)"
                diffGallery += "<div class=\"diff-card\"><img src=\"\(rel)\" alt=\"\(file)\" width=\"200\"><p>\(file)</p></div>"
            }
        }

        var historyJSON = "[]"
        let historyPath = EVPPaths.engineArtifact("history.jsonl")
        if let content = try? String(contentsOfFile: historyPath, encoding: .utf8) {
            let lines = content.split(separator: "\n").suffix(20).map { String($0) }
            historyJSON = "[\(lines.joined(separator: ","))]"
        }

        let blocking = summary.results.filter { $0.status == .fail && ($0.requirementId.hasPrefix("FLOW-") || $0.requirementId.hasPrefix("S") || $0.requirementId.hasPrefix("BRAIN-")) }
        let banner = blocking.isEmpty
            ? "<div class=\"banner pass\">Release readiness: PASS</div>"
            : "<div class=\"banner fail\">Release readiness: BLOCKED — \(blocking.count) P0 failure(s)</div>"

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>EVP Dashboard</title>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        <style>
        body{font-family:system-ui,sans-serif;margin:2rem;background:#0d1117;color:#e6edf3}
        .pass{color:#3fb950}.fail{color:#f85149}.skip{color:#8b949e}
        table{border-collapse:collapse;width:100%} th,td{border:1px solid #30363d;padding:8px;text-align:left}
        h1,h2{color:#58a6ff}
        .filters{margin:1rem 0;display:flex;gap:1rem;flex-wrap:wrap}
        .filters input,.filters select{padding:6px;background:#161b22;color:#e6edf3;border:1px solid #30363d;border-radius:4px}
        .score{font-size:2rem;font-weight:bold;color:#58a6ff}
        .banner{padding:12px 16px;border-radius:8px;margin:1rem 0;font-weight:600}
        .banner.pass{background:#1a3d2e;color:#3fb950}.banner.fail{background:#3d1a1a;color:#f85149}
        .diff-gallery{display:flex;flex-wrap:wrap;gap:1rem;margin:1rem 0}
        .diff-card{background:#161b22;padding:8px;border-radius:8px;border:1px solid #30363d}
        .metrics{display:flex;gap:2rem;flex-wrap:wrap;margin:1rem 0}
        .metric-card{background:#161b22;padding:16px;border-radius:8px;border:1px solid #30363d;min-width:140px}
        </style></head><body>
        <h1>Executive Validation Platform</h1>
        \(banner)
        <div class="metrics">
          <div class="metric-card"><div class="score">\(qualityScore)</div><div>Quality Score</div></div>
          <div class="metric-card"><div class="score">\(a11yScore)</div><div>A11y Score</div></div>
          <div class="metric-card"><div class="score">\(summary.passed)/\(summary.results.count)</div><div>Pass Rate</div></div>
        </div>
        <p>Command: <code>\(summary.command)</code> — \(summary.success ? "PASS" : "FAIL") (pass=\(summary.passed) fail=\(summary.failed) skip=\(summary.skipped))</p>
        <div class="filters">
          <input id="filterText" placeholder="Filter requirement ID..." oninput="filterTable()">
          <select id="filterStatus" onchange="filterTable()"><option value="">All statuses</option><option value="pass">Pass</option><option value="fail">Fail</option><option value="skip">Skip</option></select>
          <select id="filterLayer" onchange="filterTable()"><option value="">All layers</option><option value="L1">L1</option><option value="L2">L2</option><option value="L3">L3</option><option value="L4-R">L4-R</option><option value="L6">L6</option><option value="L7">L7</option></select>
        </div>
        <h2>Results Distribution</h2>
        <canvas id="chart" width="400" height="120"></canvas>
        <h2>Regression History</h2>
        <canvas id="historyChart" width="400" height="120"></canvas>
        <h2>Visual Diffs</h2>
        <div class="diff-gallery">\(diffGallery.isEmpty ? "<p>No visual diffs in this run.</p>" : diffGallery)</div>
        <h2>All Results</h2>
        <table id="results"><thead><tr><th>ID</th><th>Layer</th><th>Status</th><th>Duration</th><th>Source</th></tr></thead><tbody></tbody></table>
        <script>
        const data = \(resultsJSON);
        const history = \(historyJSON);
        const tbody = document.querySelector('#results tbody');
        function renderRows(rows) {
          tbody.innerHTML = rows.map(r => `<tr class="${r.status}"><td>${r.requirementId}</td><td>${r.validationLayer}</td><td>${r.status}</td><td>${r.durationMs}ms</td><td>${r.sourceDocument}</td></tr>`).join('');
        }
        function filterTable() {
          const q = document.getElementById('filterText').value.toLowerCase();
          const st = document.getElementById('filterStatus').value;
          const ly = document.getElementById('filterLayer').value;
          renderRows(data.filter(r => (!q || r.requirementId.toLowerCase().includes(q)) && (!st || r.status === st) && (!ly || r.validationLayer === ly)));
        }
        renderRows(data);
        new Chart(document.getElementById('chart'), {type:'doughnut', data:{labels:['Pass','Fail','Skip'], datasets:[{data:[\(summary.passed),\(summary.failed),\(summary.skipped)], backgroundColor:['#3fb950','#f85149','#8b949e']}]}});
        if (history.length) {
          new Chart(document.getElementById('historyChart'), {type:'line', data:{
            labels: history.map((h,i) => h.startedAt || ('Run '+i)),
            datasets:[
              {label:'Passed', data: history.map(h => h.passed), borderColor:'#3fb950', fill:false},
              {label:'Failed', data: history.map(h => h.failed), borderColor:'#f85149', fill:false}
            ]
          }});
        }
        </script></body></html>
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
                    status: index.requirements.isEmpty ? .fail : .pass,
                    evidence: ["requirementsIndexed: \(index.requirements.count)"]
                )]
            )

        case "run":
            results = try await runFullPipeline(options: options)

        case "flows":
            results = try await FlowAutomationRunner().run(options: options)

        case "visual":
            results = try await VisualRegressionRunner().run(options: options)

        case "perf":
            results = try await PerformanceRunner().run(options: options)

        case "a11y":
            results = try await AccessibilityRunner().run(options: options)

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
            let v1 = parts.isEmpty ? "v1.0.0" : parts[0]
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
        appendHistory(summary: summary)
        try ReportPipeline().writeAll(summary: summary, rtm: try? RequirementsRegistry().buildIndex())
        return summary
    }

    private func runFullPipeline(options: EVPRunOptions) async throws -> [TestResult] {
        if options.layer == .decision {
            return try DecisionRegressionRunner().run()
        }

        var results: [TestResult] = []
        let tier = options.tier ?? 2

        results.append(contentsOf: try StaticAnalysisEngine().run())
        if tier >= 2 {
            results.append(contentsOf: try await BuildValidator().run())
        }
        results.append(contentsOf: try DecisionRegressionRunner().run())

        if !options.skipUI {
            results.append(contentsOf: try await FlowAutomationRunner().run(options: options))
            results.append(contentsOf: try await VisualRegressionRunner().run(options: options))
            results.append(contentsOf: try await PerformanceRunner().run(options: options))
            results.append(contentsOf: try await AccessibilityRunner().run(options: options))
        }

        results.append(contentsOf: try await RealityReplayRunner().run(options: EVPRunOptions(fixture: "REPLAY-001")))
        results.append(contentsOf: try await CounterfactualEngine().run(options: options))
        results.append(contentsOf: try await LifeSimulatorRunner().run(options: options))
        results.append(contentsOf: try await TwinComparatorRunner().run(options: options))
        results.append(contentsOf: try await LearningSimulationRunner().run(options: options))
        results.append(contentsOf: try await MemoryDriftRunner().run(options: options))
        results.append(contentsOf: try await ExecutiveCostAuditor().run(options: options))
        results.append(contentsOf: try await TrustEvaluator().run(options: options))
        results.append(contentsOf: try await ExplainabilityValidator().run(options: options))
        results.append(contentsOf: try await GoalGraphValidator().run(options: options))
        results.append(contentsOf: try await AutonomousActionValidator().run(options: options))

        let rtm = try? RequirementsRegistry().buildIndex()
        let (score, _) = ProductionReadinessCalculator().calculate(results: results, rtm: rtm)
        results.append(TestResult(
            requirementId: "QUALITY-SCORE",
            sourceDocument: "Documentation/qa/14-production-readiness.md",
            validationLayer: .staticValidation,
            status: score >= 85 ? .pass : .fail,
            evidence: ["qualityScore: \(String(format: "%.1f", score))"]
        ))
        return results
    }

    private func appendHistory(summary: EVPRunSummary) {
        let path = EVPPaths.engineArtifact("history.jsonl")
        let line: [String: Any] = [
            "command": summary.command,
            "startedAt": ISO8601DateFormatter().string(from: summary.startedAt),
            "passed": summary.passed,
            "failed": summary.failed,
            "skipped": summary.skipped
        ]
        if let data = try? JSONSerialization.data(withJSONObject: line),
           let str = String(data: data, encoding: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write((str + "\n").data(using: .utf8)!)
                handle.closeFile()
            } else {
                try? (str + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
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
