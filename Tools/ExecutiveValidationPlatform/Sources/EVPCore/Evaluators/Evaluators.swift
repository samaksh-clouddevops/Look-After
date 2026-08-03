import Foundation

public struct ReleaseChecklistEvaluator: Sendable {
    public init() {}

    public func evaluate(results: [TestResult]) -> (verdict: String, items: [TestResult]) {
        let l3Failures = results.filter { $0.validationLayer == .decision && $0.status == .fail }
        let buildFailures = results.filter { $0.requirementId.hasPrefix("BUILD-") && $0.status == .fail }

        var items: [TestResult] = []
        let checklistPath = EVPPaths.qaDoc("12-release-checklist.md")
        let checklistExists = FileManager.default.fileExists(atPath: checklistPath)
        items.append(TestResult(
            requirementId: "RELEASE-CHECKLIST-DOC",
            sourceDocument: "Documentation/qa/12-release-checklist.md",
            validationLayer: .staticValidation,
            status: checklistExists ? .pass : .fail
        ))

        items.append(TestResult(
            requirementId: "RELEASE-L3-GATE",
            sourceDocument: "Documentation/qa/22-decision-regression.md",
            validationLayer: .decision,
            status: l3Failures.isEmpty ? .pass : .fail,
            evidence: l3Failures.map(\.requirementId),
            message: l3Failures.isEmpty ? nil : "\(l3Failures.count) decision regression failure(s)"
        ))

        items.append(TestResult(
            requirementId: "RELEASE-BUILD-GATE",
            sourceDocument: "Documentation/qa/11-regression-suite.md",
            validationLayer: .functional,
            status: buildFailures.isEmpty ? .pass : .fail,
            evidence: buildFailures.map(\.requirementId)
        ))

        let blocked = items.contains { $0.status == .fail }
        return (blocked ? "Blocked" : "Release Ready", items)
    }
}

public struct ProductionReadinessCalculator: Sendable {
    public init() {}

    public func calculate(results: [TestResult], rtm: RTMIndex?) -> (score: Double, report: [String: Any]) {
        let totalReqs = rtm?.requirements.count ?? results.count
        let automated = results.filter { $0.status == .pass }.count
        let failed = results.filter { $0.status == .fail }.count
        let implemented = results.filter { $0.status != .notImplemented }.count

        let functionalScore = implemented > 0 ? Double(automated) / Double(implemented) * 22 : 0
        let automationScore = totalReqs > 0 ? min(4.0, Double(results.filter { $0.status == .pass }.count) / Double(totalReqs) * 4) : 0
        let docScore = FileManager.default.fileExists(atPath: EVPPaths.qaDoc("14-production-readiness.md")) ? 4.0 : 0

        let decisionPasses = results.filter { $0.validationLayer == .decision && $0.status == .pass }.count
        let decisionTotal = max(1, results.filter { $0.validationLayer == .decision && $0.status != .notImplemented }.count)
        let decisionScore = Double(decisionPasses) / Double(decisionTotal) * 10

        let score = min(100, functionalScore + automationScore + docScore + decisionScore + 10) // baseline + dimensions

        let report: [String: Any] = [
            "score": score,
            "minimumForRelease": 85,
            "northStarQuestion": EVPConstants.northStarQuestion,
            "requirementsIndexed": totalReqs,
            "resultsPass": automated,
            "resultsFail": failed,
            "resultsNotImplemented": results.filter { $0.status == .notImplemented }.count,
            "verdict": score >= 85 && failed == 0 ? "Ready" : "Not Ready"
        ]
        return (score, report)
    }
}

public struct VersionComparisonBuilder: Sendable {
    public init() {}

    public func build(
        results: [TestResult],
        versionA: String,
        versionB: String
    ) -> VersionComparisonReport {
        let decisionResults = results.filter { $0.validationLayer == .decision }
        let passed = decisionResults.filter { $0.status == .pass }.count
        let total = max(1, decisionResults.count)
        let replayResults = results.filter { $0.validationLayer == .realityReplay && $0.status == .pass }

        let regressions = decisionResults.filter { $0.status == .fail }.map { "\($0.requirementId) failed on \(versionB)" }

        return VersionComparisonReport(
            question: "Would \(versionB) make better decisions over 30 days than \(versionA)?",
            evidence: VersionEvidence(
                realityReplayWeeks: replayResults.isEmpty ? 0 : 1,
                decisionsEvaluated: total,
                betterOutcomesPct: Double(passed) / Double(total) * 100,
                avgExecutiveCostDelta: 0,
                trustDelta: 0,
                satisfactionAcceptRateDelta: 0,
                regressions: regressions
            ),
            verdict: regressions.isEmpty ? "Ship" : "Blocked",
            sourceDocuments: [
                "Documentation/qa/27-reality-replay.md",
                "Documentation/qa/14-production-readiness.md"
            ]
        )
    }
}
