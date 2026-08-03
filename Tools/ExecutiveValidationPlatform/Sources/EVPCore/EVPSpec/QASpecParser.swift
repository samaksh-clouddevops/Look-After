import Foundation

public struct QASpecParser: Sendable {
    private static let idPatterns: [(ValidationLayer, NSRegularExpression)] = {
        let specs: [(ValidationLayer, String)] = [
            (.decision, #"BRAIN-DEC-\d{3}"#),
            (.realityReplay, #"REPLAY-\d{3}"#),
            (.syntheticSimulation, #"SIM-(?:DAY-)?\d{3}"#),
            (.learning, #"LO-LEARN-\d{3}"#),
            (.learning, #"MEM-\d{3}"#),
            (.executiveCost, #"LO-COST-\d{3}"#),
            (.executiveCost, #"CF-\d{3}"#),
            (.executiveCost, #"AICOST-\d{3}"#),
            (.trust, #"TRUST-\d{3}"#),
            (.trust, #"CAL-\d{3}"#),
            (.trust, #"SAT-\d{3}"#),
            (.crossCutting, #"UI-INT-[A-Z0-9-]+"#),
            (.crossCutting, #"AUTO-\d{3}"#),
            (.crossCutting, #"AUTO-LVL-\d{3}"#),
            (.crossCutting, #"GOAL-\d{3}"#),
            (.crossCutting, #"GSTAB-\d{3}"#),
            (.crossCutting, #"EXPL-\d{3}"#),
            (.syntheticSimulation, #"FAIL-\d{3}"#),
            (.functional, #"FLOW-\d{3}"#),
            (.functional, #"LO-[A-Z]+-[A-Z]+-\d{3}"#),
            (.staticValidation, #"S\d{2}"#)
        ]
        return specs.compactMap { layer, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (layer, regex)
        }
    }()

    private static let docLayerMap: [String: ValidationLayer] = [
        "01-test-strategy.md": .staticValidation,
        "02-test-matrix.md": .staticValidation,
        "03-module-test-cases.md": .functional,
        "04-screen-test-cases.md": .functional,
        "05-flow-test-cases.md": .functional,
        "06-edge-cases.md": .functional,
        "07-ai-validation.md": .executiveCost,
        "08-executive-brain-validation.md": .decision,
        "09-performance-benchmarks.md": .functional,
        "10-accessibility-checklist.md": .functional,
        "11-regression-suite.md": .functional,
        "12-release-checklist.md": .functional,
        "13-risk-assessment.md": .staticValidation,
        "14-production-readiness.md": .staticValidation,
        "15-decision-quality-framework.md": .decision,
        "16-learning-validation.md": .learning,
        "17-digital-twin-validation.md": .syntheticSimulation,
        "18-ai-hallucination-audit.md": .executiveCost,
        "19-executive-cost-validation.md": .executiveCost,
        "20-human-evaluation-protocol.md": .trust,
        "21-life-simulator.md": .syntheticSimulation,
        "22-decision-regression.md": .decision,
        "23-ui-intelligence.md": .crossCutting,
        "24-autonomous-actions.md": .crossCutting,
        "25-goal-graph-validation.md": .crossCutting,
        "26-trust-validation.md": .trust,
        "27-reality-replay.md": .realityReplay,
        "28-counterfactual-engine.md": .executiveCost,
        "29-confidence-calibration.md": .trust,
        "30-explainability-validation.md": .crossCutting,
        "31-memory-drift-validation.md": .learning,
        "32-goal-stability.md": .crossCutting,
        "33-autonomy-budget.md": .crossCutting,
        "34-human-satisfaction.md": .trust,
        "35-ai-cost-validation.md": .executiveCost,
        "36-failure-recovery.md": .syntheticSimulation
    ]

    public init() {}

    public func parseAllDocuments(qaRoot: String = EVPPaths.qaRoot) throws -> [QARequirement] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: qaRoot) else {
            throw EVPError.io("Cannot read QA directory: \(qaRoot)")
        }

        var requirements: [QARequirement] = []
        var seen = Set<String>()

        for file in files.sorted() where file.hasSuffix(".md") && file != "README.md" && file != "brain-bugs.md" {
            let path = (qaRoot as NSString).appendingPathComponent(file)
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let defaultLayer = Self.docLayerMap[file] ?? .staticValidation
            let parsed = parseDocument(content: content, fileName: file, defaultLayer: defaultLayer)
            for req in parsed where seen.insert(req.id).inserted {
                requirements.append(req)
            }
        }

        let fixtureReqs = try parseFixtureIDs(qaRoot: qaRoot)
        for req in fixtureReqs where seen.insert(req.id).inserted {
            requirements.append(req)
        }

        return requirements.sorted { $0.id < $1.id }
    }

    public func parseDocument(content: String, fileName: String, defaultLayer: ValidationLayer) -> [QARequirement] {
        var results: [QARequirement] = []
        var seen = Set<String>()

        for (layer, regex) in Self.idPatterns {
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            regex.enumerateMatches(in: content, range: range) { match, _, _ in
                guard let match, let idRange = Range(match.range, in: content) else { return }
                let id = String(content[idRange])
                guard seen.insert(id).inserted else { return }

                let effectiveLayer = layerForID(id, fallback: defaultLayer)
                let title = extractTitle(near: id, in: content)
                let priority = extractPriority(near: id, in: content)
                let automation = automationStatus(for: id, fileName: fileName)

                results.append(QARequirement(
                    id: id,
                    sourceDocument: "Documentation/qa/\(fileName)",
                    validationLayer: effectiveLayer,
                    priority: priority,
                    title: title,
                    automationStatus: automation
                ))
            }
        }

        return results
    }

    private func layerForID(_ id: String, fallback: ValidationLayer) -> ValidationLayer {
        if id.hasPrefix("BRAIN-DEC") { return .decision }
        if id.hasPrefix("REPLAY") { return .realityReplay }
        if id.hasPrefix("SIM") || id.hasPrefix("FAIL") { return .syntheticSimulation }
        if id.hasPrefix("MEM") || id.hasPrefix("LO-LEARN") { return .learning }
        if id.hasPrefix("CF") || id.hasPrefix("AICOST") || id.hasPrefix("LO-COST") { return .executiveCost }
        if id.hasPrefix("TRUST") || id.hasPrefix("CAL") || id.hasPrefix("SAT") { return .trust }
        if id.hasPrefix("FLOW") || id.hasPrefix("LO-") { return .functional }
        return fallback
    }

    private func extractTitle(near id: String, in content: String) -> String? {
        guard let range = content.range(of: id) else { return nil }
        let lineStart = content[..<range.lowerBound].lastIndex(of: "\n").map { content.index(after: $0) } ?? content.startIndex
        let lineEnd = content[range.upperBound...].firstIndex(of: "\n") ?? content.endIndex
        let line = String(content[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces)
        if line.contains("—") {
            return line.components(separatedBy: "—").dropFirst().joined(separator: "—").trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func extractPriority(near id: String, in content: String) -> String? {
        guard let idRange = content.range(of: id) else { return nil }
        let window = content[idRange.lowerBound...].prefix(800)
        if let match = window.range(of: #"Priority \| P[0-3]"#, options: .regularExpression) {
            return String(window[match]).components(separatedBy: "|").last?.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func automationStatus(for id: String, fileName: String) -> AutomationStatus {
        if id.hasPrefix("BRAIN-DEC") { return .automated }
        if id.hasPrefix("REPLAY") { return .scaffold }
        if fileName.hasPrefix("22-") || fileName.hasPrefix("27-") { return .scaffold }
        if fileName.contains("simulator") || fileName.hasPrefix("21-") { return .scaffold }
        return .manual
    }

    private func parseFixtureIDs(qaRoot: String) throws -> [QARequirement] {
        let fixturesRoot = (qaRoot as NSString).appendingPathComponent("fixtures")
        var results: [QARequirement] = []
        guard let enumerator = FileManager.default.enumerator(atPath: fixturesRoot) else { return [] }

        while let relative = enumerator.nextObject() as? String, relative.hasSuffix(".json") {
            let path = (fixturesRoot as NSString).appendingPathComponent(relative)
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else { continue }
            let source = json["sourceDocument"] as? String ?? "Documentation/qa/fixtures/\(relative)"
            let layer: ValidationLayer = layerForID(id, fallback: .decision)
            results.append(QARequirement(
                id: id,
                sourceDocument: source,
                validationLayer: layer,
                automationStatus: id.hasPrefix("BRAIN-DEC") ? .automated : .scaffold
            ))
        }
        return results
    }
}

public enum EVPError: Error, CustomStringConvertible {
    case io(String)
    case parse(String)
    case runner(String)

    public var description: String {
        switch self {
        case .io(let m), .parse(let m), .runner(let m): return m
        }
    }
}
