import XCTest
import TourPlacement
// Geometry types come from TourPlacement (CoreGraphics on Apple, shim on Linux).

final class TourPlacementEngineTests: XCTestCase {

    private let phone = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let safe = TourEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    private func metrics(
        tabBar: CGRect = CGRect(x: 0, y: 760, width: 390, height: 84),
        keyboard: CGRect = .null,
        cardSize: CGSize = CGSize(width: 320, height: 200)
    ) -> TourLayoutMetrics {
        TourLayoutMetrics(
            screenBounds: phone,
            safeAreaInsets: safe,
            keyboardFrame: keyboard,
            tabBarFrame: tabBar,
            cardSize: cardSize,
            cardMargin: 16,
            highlightPadding: 10,
            minimumGap: 12
        )
    }

    func testPlacesCardBelowWhenRoomExists() {
        let highlight = CGRect(x: 40, y: 120, width: 300, height: 80)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: metrics())
        XCTAssertEqual(proposal.side, .below)
        XCTAssertGreaterThan(proposal.cardFrame.minY, highlight.maxY)
        XCTAssertFalse(TourPlacementEngine.hasCollision(
            card: proposal.cardFrame,
            highlight: highlight.insetBy(dx: -10, dy: -10),
            metrics: metrics()
        ))
        XCTAssertTrue(metrics().usableBounds.contains(proposal.cardFrame))
    }

    func testPlacesCardAboveWhenTargetIsLow() {
        let highlight = CGRect(x: 40, y: 620, width: 300, height: 60)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: metrics())
        XCTAssertEqual(proposal.side, .above)
        XCTAssertLessThan(proposal.cardFrame.maxY, highlight.minY)
        XCTAssertEqual(proposal.arrowEdge, .bottom)
    }

    func testCenterWhenNoHighlight() {
        let proposal = TourPlacementEngine.propose(highlight: nil, metrics: metrics())
        XCTAssertEqual(proposal.side, .center)
        XCTAssertEqual(proposal.arrowEdge, .none)
        XCTAssertTrue(metrics().usableBounds.contains(proposal.cardFrame))
    }

    func testNeverOverlapsHighlight() {
        let samples: [CGRect] = [
            CGRect(x: 20, y: 100, width: 200, height: 100),
            CGRect(x: 100, y: 400, width: 180, height: 120),
            CGRect(x: 40, y: 700, width: 310, height: 44),
            CGRect(x: 0, y: 780, width: 80, height: 50),
            CGRect(x: 155, y: 380, width: 80, height: 80),
        ]
        let m = metrics()
        for highlight in samples {
            let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: m)
            let padded = highlight.insetBy(dx: -m.highlightPadding, dy: -m.highlightPadding)
            let overlap = proposal.cardFrame.intersectionArea(with: padded.expanded(by: m.minimumGap))
            XCTAssertLessThan(overlap, 0.5, "Card overlapped highlight for \(highlight)")
            XCTAssertGreaterThanOrEqual(proposal.cardFrame.minX, m.usableBounds.minX - 0.5)
            XCTAssertLessThanOrEqual(proposal.cardFrame.maxX, m.usableBounds.maxX + 0.5)
        }
    }

    func testKeyboardReducesUsableArea() {
        let keyboard = CGRect(x: 0, y: 480, width: 390, height: 364)
        let m = metrics(keyboard: keyboard)
        XCTAssertLessThan(m.usableBounds.maxY, keyboard.minY)
        let highlight = CGRect(x: 40, y: 100, width: 300, height: 60)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: m)
        XCTAssertLessThanOrEqual(proposal.cardFrame.maxY, m.usableBounds.maxY + 0.5)
    }

    func testArrowPointsTowardHighlight() {
        let highlight = CGRect(x: 40, y: 120, width: 300, height: 80)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: metrics())
        XCTAssertNotEqual(proposal.arrowEdge, .none)
        switch proposal.arrowEdge {
        case .top:
            XCTAssertEqual(proposal.arrowTip.y, proposal.cardFrame.minY, accuracy: 0.5)
        case .bottom:
            XCTAssertEqual(proposal.arrowTip.y, proposal.cardFrame.maxY, accuracy: 0.5)
        case .left:
            XCTAssertEqual(proposal.arrowTip.x, proposal.cardFrame.minX, accuracy: 0.5)
        case .right:
            XCTAssertEqual(proposal.arrowTip.x, proposal.cardFrame.maxX, accuracy: 0.5)
        case .none:
            XCTFail("Expected arrow")
        }
    }

    func testOffscreenHighlightRequestsScroll() {
        let highlight = CGRect(x: 40, y: 1200, width: 300, height: 80)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: metrics())
        XCTAssertTrue(proposal.needsScroll)
    }

    func testSmallPhoneSELayout() {
        let se = CGRect(x: 0, y: 0, width: 320, height: 568)
        let m = TourLayoutMetrics(
            screenBounds: se,
            safeAreaInsets: TourEdgeInsets(top: 20, left: 0, bottom: 0, right: 0),
            tabBarFrame: CGRect(x: 0, y: 500, width: 320, height: 68),
            cardSize: CGSize(width: 288, height: 200)
        )
        let highlight = CGRect(x: 16, y: 80, width: 288, height: 70)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: m)
        XCTAssertTrue(m.usableBounds.intersects(proposal.cardFrame) || m.usableBounds.contains(proposal.cardFrame.center))
        let padded = highlight.insetBy(dx: -10, dy: -10)
        XCTAssertLessThan(proposal.cardFrame.intersectionArea(with: padded.expanded(by: 12)), 0.5)
    }

    func testLandscapeLayout() {
        let landscape = CGRect(x: 0, y: 0, width: 844, height: 390)
        let m = TourLayoutMetrics(
            screenBounds: landscape,
            safeAreaInsets: TourEdgeInsets(top: 0, left: 59, bottom: 21, right: 59),
            tabBarFrame: CGRect(x: 0, y: 320, width: 844, height: 70),
            cardSize: CGSize(width: 360, height: 180)
        )
        let highlight = CGRect(x: 100, y: 40, width: 200, height: 50)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: m)
        XCTAssertFalse(TourPlacementEngine.hasCollision(
            card: proposal.cardFrame,
            highlight: highlight.insetBy(dx: -10, dy: -10),
            metrics: m
        ))
    }

    func testCollisionAreaDetectsOverlap() {
        let m = metrics()
        let card = CGRect(x: 50, y: 100, width: 200, height: 100)
        let highlight = CGRect(x: 100, y: 120, width: 100, height: 40)
        XCTAssertTrue(TourPlacementEngine.hasCollision(card: card, highlight: highlight, metrics: m))
        let free = CGRect(x: 50, y: 300, width: 200, height: 100)
        XCTAssertFalse(TourPlacementEngine.hasCollision(card: free, highlight: highlight, metrics: m))
    }

    func testPlacementSnapshotFixtureStable() {
        let highlight = CGRect(x: 45, y: 140, width: 300, height: 90)
        let proposal = TourPlacementEngine.propose(highlight: highlight, metrics: metrics())
        XCTAssertEqual(proposal.side, .below)
        XCTAssertEqual(proposal.arrowEdge, .top)
        let padded = highlight.insetBy(dx: -10, dy: -10)
        XCTAssertGreaterThanOrEqual(proposal.cardFrame.minY, padded.maxY + 12 - 0.5)
        XCTAssertEqual(proposal.cardFrame.width, 320, accuracy: 0.5)
        XCTAssertTrue(metrics().usableBounds.contains(CGPoint(x: proposal.cardFrame.midX, y: proposal.cardFrame.midY)))
    }
}
