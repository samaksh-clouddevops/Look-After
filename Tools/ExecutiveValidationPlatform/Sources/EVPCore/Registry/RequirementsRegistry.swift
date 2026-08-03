import Foundation

public struct RequirementsRegistry: Sendable {
    private let parser = QASpecParser()

    public init() {}

    public func buildIndex(qaRoot: String = EVPPaths.qaRoot) throws -> RTMIndex {
        let requirements = try parser.parseAllDocuments(qaRoot: qaRoot)
        var counts: [String: Int] = [:]
        for layer in ValidationLayer.allCases {
            counts[layer.rawValue] = requirements.filter { $0.validationLayer == layer }.count
        }
        return RTMIndex(
            generatedAt: Date(),
            requirements: requirements,
            countsByLayer: counts,
            northStarQuestion: EVPConstants.northStarQuestion
        )
    }

    public func writeRTM(to outputDir: String = EVPPaths.engineOutput, qaRoot: String = EVPPaths.qaRoot) throws -> RTMIndex {
        let fm = FileManager.default
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let index = try buildIndex(qaRoot: qaRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonURL = URL(fileURLWithPath: (outputDir as NSString).appendingPathComponent("rtm.json"))
        try encoder.encode(index).write(to: jsonURL)

        let md = renderMarkdown(index: index)
        let mdURL = URL(fileURLWithPath: (outputDir as NSString).appendingPathComponent("rtm.md"))
        try md.write(to: mdURL, atomically: true, encoding: .utf8)

        return index
    }

    public func loadRTM(from outputDir: String = EVPPaths.engineOutput) throws -> RTMIndex {
        let path = (outputDir as NSString).appendingPathComponent("rtm.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RTMIndex.self, from: data)
    }

    public func trace(requirementId: String, qaRoot: String = EVPPaths.qaRoot, outputDir: String = EVPPaths.engineOutput) throws -> String {
        let index = try buildIndex(qaRoot: qaRoot)
        guard let req = index.requirements.first(where: { $0.id == requirementId }) else {
            throw EVPError.parse("Requirement not found: \(requirementId)")
        }

        let docPath = (EVPPaths.repoRoot as NSString).appendingPathComponent(req.sourceDocument)
        var output = "# Trace: \(requirementId)\n\n"
        output += "- **Source:** `\(req.sourceDocument)`\n"
        output += "- **Layer:** \(req.validationLayer.rawValue) (\(req.validationLayer.displayName))\n"
        if let p = req.priority { output += "- **Priority:** \(p)\n" }
        if let t = req.title { output += "- **Title:** \(t)\n" }
        output += "- **Automation:** \(req.automationStatus.rawValue)\n\n"

        if FileManager.default.fileExists(atPath: docPath) {
            let content = try String(contentsOfFile: docPath, encoding: .utf8)
            if let excerpt = excerpt(for: requirementId, in: content) {
                output += "## Doc excerpt\n\n```\n\(excerpt)\n```\n\n"
            }
        }

        let fixtureDir = EVPPaths.fixturesRoot
        if let fixture = findFixture(named: requirementId, in: fixtureDir) {
            output += "## Fixture\n\n`\(fixture)`\n\n"
            let fixtureContent = try String(contentsOfFile: fixture, encoding: .utf8)
            output += "```json\n\(fixtureContent.prefix(2000))\n```\n"
        }

        let resultsPath = (outputDir as NSString).appendingPathComponent("results.json")
        if FileManager.default.fileExists(atPath: resultsPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: resultsPath)),
           let summary = try? JSONDecoder().decode(EVPRunSummary.self, from: data),
           let result = summary.results.first(where: { $0.requirementId == requirementId }) {
            output += "\n## Last result\n\n- Status: **\(result.status.rawValue)**\n"
            if let msg = result.message { output += "- Message: \(msg)\n" }
        }

        return output
    }

    private func excerpt(for id: String, in content: String) -> String? {
        guard let range = content.range(of: id) else { return nil }
        let start = content.index(range.lowerBound, offsetBy: -200, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: 600, limitedBy: content.endIndex) ?? content.endIndex
        return String(content[start..<end])
    }

    private func findFixture(named id: String, in root: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return nil }
        let slug = id.lowercased().replacingOccurrences(of: "-", with: "_")
        while let relative = enumerator.nextObject() as? String, relative.hasSuffix(".json") {
            if relative.lowercased().contains(slug) {
                return (root as NSString).appendingPathComponent(relative)
            }
        }
        return nil
    }

    private func renderMarkdown(index: RTMIndex) -> String {
        var md = "# Requirements Traceability Matrix\n\n"
        md += "**Generated:** \(index.generatedAt.formatted())\n\n"
        md += "**North-star:** \(index.northStarQuestion)\n\n"
        md += "## Layer counts\n\n| Layer | Count |\n|-------|-------|\n"
        for layer in ValidationLayer.allCases {
            md += "| \(layer.rawValue) \(layer.displayName) | \(index.countsByLayer[layer.rawValue, default: 0]) |\n"
        }
        md += "\n## Requirements (\(index.requirements.count))\n\n"
        md += "| ID | Layer | Priority | Source | Automation |\n"
        md += "|----|-------|----------|--------|------------|\n"
        for req in index.requirements.prefix(500) {
            md += "| \(req.id) | \(req.validationLayer.rawValue) | \(req.priority ?? "—") | \(req.sourceDocument) | \(req.automationStatus.rawValue) |\n"
        }
        if index.requirements.count > 500 {
            md += "\n*… and \(index.requirements.count - 500) more (see rtm.json)*\n"
        }
        return md
    }
}
