import XCTest
@testable import LookAfterIntegrations

final class EmailTriageClassifierTests: XCTestCase {
    func testHeuristicBillClassification() async {
        let thread = EmailThreadSummary(
            id: "1",
            subject: "Invoice due",
            sender: "billing@test.com",
            snippet: "Your bill is due Friday"
        )
        let item = await EmailTriageClassifier.classify(threads: [thread])
        XCTAssertEqual(item.first?.action, .lifeAdmin)
    }
}
