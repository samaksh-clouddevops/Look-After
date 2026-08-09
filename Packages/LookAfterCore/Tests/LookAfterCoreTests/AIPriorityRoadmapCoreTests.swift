import XCTest
import LookAfterCore

final class TravelDisruptionDetectorTests: XCTestCase {
    func testDetectsFlightOnTimeline() {
        let event = LifeTimelineEvent(
            id: "cal-1",
            kind: .travel,
            title: "Flight to NYC",
            date: Date().addingTimeInterval(3600)
        )
        TravelDisruptionDetector.resetFingerprint()
        _ = TravelDisruptionDetector.evaluate(timelineEvents: [event])
        let disruption = TravelDisruptionDetector.evaluate(timelineEvents: [event])
        XCTAssertNotNil(disruption)
    }
}

final class CaptureGraphStoreTests: XCTestCase {
    func testRecordsEdge() async {
        await CaptureGraphStore.shared.removeEdges(forInboxID: "inbox-1")
        await CaptureGraphIndexer.indexTask(inboxID: "inbox-1", taskID: "task-1")
        let edges = await CaptureGraphStore.shared.edges(fromInboxID: "inbox-1")
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges.first?.targetEntityID, "task-1")
    }
}
