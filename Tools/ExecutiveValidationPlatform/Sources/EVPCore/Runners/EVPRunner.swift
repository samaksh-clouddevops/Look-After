import Foundation

public protocol EVPRunner: Sendable {
    var name: String { get }
    func run(options: EVPRunOptions) async throws -> [TestResult]
}

public struct EVPRunOptions: Sendable {
    public var tier: Int?
    public var layer: ValidationLayer?
    public var requirementId: String?
    public var days: Int?
    public var scenario: String?
    public var fixture: String?
    public var compareVersions: (String, String)?
    public var failScenario: String?

    public init(
        tier: Int? = nil,
        layer: ValidationLayer? = nil,
        requirementId: String? = nil,
        days: Int? = nil,
        scenario: String? = nil,
        fixture: String? = nil,
        compareVersions: (String, String)? = nil,
        failScenario: String? = nil
    ) {
        self.tier = tier
        self.layer = layer
        self.requirementId = requirementId
        self.days = days
        self.scenario = scenario
        self.fixture = fixture
        self.compareVersions = compareVersions
        self.failScenario = failScenario
    }
}

public struct ScaffoldRunner: Sendable {
    public let name: String
    public let layer: ValidationLayer
    public let sourceDocument: String
    public let requirementPrefix: String

    public init(name: String, layer: ValidationLayer, sourceDocument: String, requirementPrefix: String) {
        self.name = name
        self.layer = layer
        self.sourceDocument = sourceDocument
        self.requirementPrefix = requirementPrefix
    }

    public func run(options: EVPRunOptions) async throws -> [TestResult] {
        let registry = RequirementsRegistry()
        let index = try registry.buildIndex()
        let matches = index.requirements.filter { $0.id.hasPrefix(requirementPrefix) || requirementPrefix.isEmpty && $0.validationLayer == layer }
        let filtered: [QARequirement]
        if let id = options.requirementId {
            filtered = matches.filter { $0.id == id }
        } else if let scenario = options.scenario ?? options.fixture ?? options.failScenario {
            filtered = matches.filter { $0.id == scenario }
        } else {
            filtered = Array(matches.prefix(3))
        }

        if filtered.isEmpty {
            return [TestResult(
                requirementId: requirementPrefix,
                sourceDocument: sourceDocument,
                validationLayer: layer,
                status: .notImplemented,
                evidence: ["Phase 1 scaffold — no matching requirements indexed yet"]
            )]
        }

        return filtered.map { req in
            TestResult(
                requirementId: req.id,
                sourceDocument: req.sourceDocument,
                validationLayer: layer,
                status: .notImplemented,
                evidence: ["Phase 1 scaffold for \(name)", "Implement in Phase 2"]
            )
        }
    }
}
