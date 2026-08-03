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
    public var skipUI: Bool

    public init(
        tier: Int? = nil,
        layer: ValidationLayer? = nil,
        requirementId: String? = nil,
        days: Int? = nil,
        scenario: String? = nil,
        fixture: String? = nil,
        compareVersions: (String, String)? = nil,
        failScenario: String? = nil,
        skipUI: Bool = false
    ) {
        self.tier = tier
        self.layer = layer
        self.requirementId = requirementId
        self.days = days
        self.scenario = scenario
        self.fixture = fixture
        self.compareVersions = compareVersions
        self.failScenario = failScenario
        self.skipUI = skipUI
    }
}
