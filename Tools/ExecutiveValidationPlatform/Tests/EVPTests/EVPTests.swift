import XCTest
@testable import EVPCore

final class QASpecParserTests: XCTestCase {
    func testParseDocumentsFindsRequirements() throws {
        let root = EVPPaths.findRepoRoot()
        let qaRoot = (root as NSString).appendingPathComponent("Documentation/qa")
        guard FileManager.default.fileExists(atPath: qaRoot) else {
            throw XCTSkip("QA docs not found from \(root)")
        }
        let parser = QASpecParser()
        let reqs = try parser.parseAllDocuments(qaRoot: qaRoot)
        XCTAssertGreaterThan(reqs.count, 50)
        XCTAssertTrue(reqs.contains { $0.id.hasPrefix("BRAIN-DEC") })
        XCTAssertTrue(reqs.contains { $0.id.hasPrefix("REPLAY") })
    }
}

final class DecisionRegressionTests: XCTestCase {
    func testBrainDecFixturesExist() throws {
        let dir = EVPPaths.fixture("decisions")
        guard FileManager.default.fileExists(atPath: dir) else {
            throw XCTSkip("Decision fixtures not found")
        }
        let results = try DecisionRegressionRunner().run(fixturesDir: dir)
        XCTAssertGreaterThanOrEqual(results.count, 3)
    }
}
