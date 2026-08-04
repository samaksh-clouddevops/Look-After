import CoreGraphics
import Foundation

/// Pure layout engine: measures obstacles, scores candidates, never overlaps the highlight.
public enum TourPlacementEngine {

    // MARK: - Public API

    /// Compute the best collision-free card placement for a highlight.
    public static func propose(
        highlight rawHighlight: CGRect?,
        metrics: TourLayoutMetrics
    ) -> TourLayoutProposal {
        let usable = metrics.usableBounds
        guard usable.width > 1, usable.height > 1 else {
            return centeredFallback(highlight: rawHighlight, metrics: metrics, needsScroll: false)
        }

        guard var highlight = rawHighlight, highlight.isValidObstacle else {
            return centeredFallback(highlight: nil, metrics: metrics, needsScroll: false)
        }

        highlight = highlight.expanded(by: metrics.highlightPadding)
            .integral
        let clampedHighlight = highlight.intersection(metrics.screenBounds)
        if clampedHighlight.isNull || !clampedHighlight.isValidObstacle {
            return centeredFallback(highlight: highlight, metrics: metrics, needsScroll: true)
        }
        highlight = clampedHighlight

        let visibleOverlap = highlight.intersection(usable)
        let highlightFullyVisible = !visibleOverlap.isNull
            && visibleOverlap.width >= highlight.width * 0.9
            && visibleOverlap.height >= highlight.height * 0.9

        var candidates = buildCandidates(highlight: highlight, metrics: metrics, usable: usable)
        candidates = candidates.compactMap { candidate in
            refined(candidate, highlight: highlight, metrics: metrics, usable: usable)
        }

        if let best = candidates.max(by: { $0.score < $1.score }), best.score > 0 {
            var result = best
            if !highlightFullyVisible {
                result.needsScroll = true
                result.suggestedScrollOffset = scrollOffsetToCenter(
                    highlight: highlight,
                    usable: usable
                )
            }
            return result
        }

        // No collision-free fit — suggest scroll then floating fallback.
        var fallback = centeredFallback(highlight: highlight, metrics: metrics, needsScroll: true)
        fallback.suggestedScrollOffset = scrollOffsetToMakeRoom(
            highlight: highlight,
            cardHeight: metrics.cardSize.height,
            metrics: metrics,
            usable: usable
        )
        return fallback
    }

    /// True when card rect intersects any forbidden region (including highlight).
    public static func hasCollision(
        card: CGRect,
        highlight: CGRect?,
        metrics: TourLayoutMetrics
    ) -> Bool {
        !collisionArea(card: card, highlight: highlight, metrics: metrics).isZero
    }

    /// Total intersecting area with obstacles. Lower is better.
    public static func collisionArea(
        card: CGRect,
        highlight: CGRect?,
        metrics: TourLayoutMetrics
    ) -> CGFloat {
        var area: CGFloat = 0
        let usable = metrics.usableBounds
        if !usable.contains(card) {
            // Penalize any part of the card outside usable bounds.
            let inside = card.intersection(usable)
            let insideArea = inside.isNull ? 0 : inside.width * inside.height
            area += max(0, card.width * card.height - insideArea)
        }
        if let highlight, highlight.isValidObstacle {
            area += card.intersectionArea(with: highlight.expanded(by: metrics.minimumGap))
        }
        for obstacle in obstacleFrames(metrics: metrics) {
            area += card.intersectionArea(with: obstacle)
        }
        return area
    }

    public static func scrollOffsetToCenter(highlight: CGRect, usable: CGRect) -> CGFloat {
        let targetCenterY = usable.midY
        return highlight.midY - targetCenterY
    }

    // MARK: - Candidates

    private static func buildCandidates(
        highlight: CGRect,
        metrics: TourLayoutMetrics,
        usable: CGRect
    ) -> [TourLayoutProposal] {
        let size = metrics.cardSize
        let gap = metrics.minimumGap
        let sides = metrics.preferredSides
        var result: [TourLayoutProposal] = []

        for side in sides {
            switch side {
            case .above:
                let y = highlight.minY - gap - size.height
                let x = clampedX(ideal: highlight.midX - size.width / 2, width: size.width, usable: usable, margin: metrics.cardMargin)
                result.append(proposal(
                    origin: CGPoint(x: x, y: y),
                    size: size,
                    side: .above,
                    highlight: highlight
                ))
            case .below:
                let y = highlight.maxY + gap
                let x = clampedX(ideal: highlight.midX - size.width / 2, width: size.width, usable: usable, margin: metrics.cardMargin)
                result.append(proposal(
                    origin: CGPoint(x: x, y: y),
                    size: size,
                    side: .below,
                    highlight: highlight
                ))
            case .left:
                let x = highlight.minX - gap - size.width
                let y = clampedY(ideal: highlight.midY - size.height / 2, height: size.height, usable: usable, margin: metrics.cardMargin)
                result.append(proposal(
                    origin: CGPoint(x: x, y: y),
                    size: size,
                    side: .left,
                    highlight: highlight
                ))
            case .right:
                let x = highlight.maxX + gap
                let y = clampedY(ideal: highlight.midY - size.height / 2, height: size.height, usable: usable, margin: metrics.cardMargin)
                result.append(proposal(
                    origin: CGPoint(x: x, y: y),
                    size: size,
                    side: .right,
                    highlight: highlight
                ))
            case .center, .floating:
                let origin = CGPoint(
                    x: usable.midX - size.width / 2,
                    y: usable.midY - size.height / 2
                )
                result.append(proposal(
                    origin: origin,
                    size: size,
                    side: side,
                    highlight: highlight
                ))
            }
        }
        return result
    }

    private static func proposal(
        origin: CGPoint,
        size: CGSize,
        side: TourCardSide,
        highlight: CGRect
    ) -> TourLayoutProposal {
        let frame = CGRect(origin: origin, size: size)
        let arrow = arrow(for: side, card: frame, highlight: highlight)
        return TourLayoutProposal(
            cardFrame: frame,
            highlightFrame: highlight,
            side: side,
            arrowEdge: arrow.edge,
            arrowTip: arrow.tip
        )
    }

    private static func refined(
        _ candidate: TourLayoutProposal,
        highlight: CGRect,
        metrics: TourLayoutMetrics,
        usable: CGRect
    ) -> TourLayoutProposal? {
        var frame = candidate.cardFrame

        // Keep card inside usable bounds when possible.
        if frame.width <= usable.width {
            frame.origin.x = min(max(frame.minX, usable.minX + metrics.cardMargin),
                                 usable.maxX - metrics.cardMargin - frame.width)
        }
        if frame.height <= usable.height {
            frame.origin.y = min(max(frame.minY, usable.minY + metrics.cardMargin),
                                 usable.maxY - metrics.cardMargin - frame.height)
        }

        let collisions = collisionArea(card: frame, highlight: highlight, metrics: metrics)
        guard collisions < 0.5 else { return nil }

        var scored = candidate
        scored.cardFrame = frame
        let arrow = arrow(for: candidate.side, card: frame, highlight: highlight)
        scored.arrowEdge = arrow.edge
        scored.arrowTip = arrow.tip
        scored.score = score(
            side: candidate.side,
            card: frame,
            highlight: highlight,
            metrics: metrics,
            preferred: metrics.preferredSides
        )
        return scored
    }

    private static func score(
        side: TourCardSide,
        card: CGRect,
        highlight: CGRect,
        metrics: TourLayoutMetrics,
        preferred: [TourCardSide]
    ) -> CGFloat {
        var value: CGFloat = 1000

        // Preference order bonus
        if let index = preferred.firstIndex(of: side) {
            value += CGFloat(preferred.count - index) * 40
        }

        // Prefer closer cards (shorter guide distance)
        let distance = hypot(card.midX - highlight.midX, card.midY - highlight.midY)
        value -= distance * 0.15

        // Prefer cards that stay fully inside usable bounds
        let usable = metrics.usableBounds
        if usable.contains(card) {
            value += 80
        } else {
            value -= 200
        }

        // Slight preference for vertical placements (more natural for phone)
        if side == .above || side == .below {
            value += 25
        }
        if side == .center || side == .floating {
            value -= 30
        }

        // Penalize residual collision softly (should already be near zero)
        value -= collisionArea(card: card, highlight: highlight, metrics: metrics) * 5

        return value
    }

    private static func arrow(
        for side: TourCardSide,
        card: CGRect,
        highlight: CGRect
    ) -> (edge: TourArrowEdge, tip: CGPoint) {
        switch side {
        case .above:
            let x = min(max(highlight.midX, card.minX + 20), card.maxX - 20)
            return (.bottom, CGPoint(x: x, y: card.maxY))
        case .below:
            let x = min(max(highlight.midX, card.minX + 20), card.maxX - 20)
            return (.top, CGPoint(x: x, y: card.minY))
        case .left:
            let y = min(max(highlight.midY, card.minY + 20), card.maxY - 20)
            return (.right, CGPoint(x: card.maxX, y: y))
        case .right:
            let y = min(max(highlight.midY, card.minY + 20), card.maxY - 20)
            return (.left, CGPoint(x: card.minX, y: y))
        case .center, .floating:
            return (.none, card.center)
        }
    }

    private static func clampedX(ideal: CGFloat, width: CGFloat, usable: CGRect, margin: CGFloat) -> CGFloat {
        let minX = usable.minX + margin
        let maxX = usable.maxX - margin - width
        guard maxX >= minX else { return usable.midX - width / 2 }
        return min(max(ideal, minX), maxX)
    }

    private static func clampedY(ideal: CGFloat, height: CGFloat, usable: CGRect, margin: CGFloat) -> CGFloat {
        let minY = usable.minY + margin
        let maxY = usable.maxY - margin - height
        guard maxY >= minY else { return usable.midY - height / 2 }
        return min(max(ideal, minY), maxY)
    }

    private static func obstacleFrames(metrics: TourLayoutMetrics) -> [CGRect] {
        var frames: [CGRect] = []
        if metrics.keyboardFrame.isValidObstacle { frames.append(metrics.keyboardFrame) }
        if metrics.navigationBarFrame.isValidObstacle { frames.append(metrics.navigationBarFrame) }
        if metrics.tabBarFrame.isValidObstacle { frames.append(metrics.tabBarFrame) }
        if metrics.bottomSheetFrame.isValidObstacle { frames.append(metrics.bottomSheetFrame) }
        frames.append(contentsOf: metrics.floatingObstacleFrames.filter(\.isValidObstacle))
        return frames
    }

    private static func centeredFallback(
        highlight: CGRect?,
        metrics: TourLayoutMetrics,
        needsScroll: Bool
    ) -> TourLayoutProposal {
        let usable = metrics.usableBounds
        let size = metrics.cardSize
        var origin = CGPoint(
            x: usable.midX - size.width / 2,
            y: usable.midY - size.height / 2
        )
        if size.width <= usable.width {
            origin.x = clampedX(ideal: origin.x, width: size.width, usable: usable, margin: metrics.cardMargin)
        }
        if size.height <= usable.height {
            origin.y = clampedY(ideal: origin.y, height: size.height, usable: usable, margin: metrics.cardMargin)
        }
        let frame = CGRect(origin: origin, size: size)
        let hl = highlight ?? .null
        // If center collides with highlight, push card to the larger free region.
        var resolved = frame
        if let highlight, highlight.isValidObstacle,
           collisionArea(card: frame, highlight: highlight, metrics: metrics) > 0.5 {
            resolved = largestFreeCardFrame(highlight: highlight, metrics: metrics, usable: usable) ?? frame
        }
        let side: TourCardSide = highlight == nil ? .center : .floating
        let arrowInfo = arrow(for: side == .center ? .center : inferSide(card: resolved, highlight: hl), card: resolved, highlight: hl)
        return TourLayoutProposal(
            cardFrame: resolved,
            highlightFrame: hl.isNull ? .zero : hl,
            side: side,
            arrowEdge: highlight == nil ? .none : arrowInfo.edge,
            arrowTip: arrowInfo.tip,
            needsScroll: needsScroll,
            suggestedScrollOffset: 0,
            score: 1
        )
    }

    private static func inferSide(card: CGRect, highlight: CGRect) -> TourCardSide {
        guard highlight.isValidObstacle else { return .center }
        let dx = card.midX - highlight.midX
        let dy = card.midY - highlight.midY
        if abs(dy) >= abs(dx) {
            return dy < 0 ? .above : .below
        }
        return dx < 0 ? .left : .right
    }

    private static func largestFreeCardFrame(
        highlight: CGRect,
        metrics: TourLayoutMetrics,
        usable: CGRect
    ) -> CGRect? {
        let size = metrics.cardSize
        let gap = metrics.minimumGap
        let regions: [(TourCardSide, CGRect)] = [
            (.above, CGRect(x: usable.minX, y: usable.minY, width: usable.width, height: max(0, highlight.minY - gap - usable.minY))),
            (.below, CGRect(x: usable.minX, y: highlight.maxY + gap, width: usable.width, height: max(0, usable.maxY - highlight.maxY - gap))),
            (.left, CGRect(x: usable.minX, y: usable.minY, width: max(0, highlight.minX - gap - usable.minX), height: usable.height)),
            (.right, CGRect(x: highlight.maxX + gap, y: usable.minY, width: max(0, usable.maxX - highlight.maxX - gap), height: usable.height)),
        ]
        guard let best = regions.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }),
              best.1.width >= size.width * 0.5,
              best.1.height >= size.height * 0.5 else {
            return nil
        }
        let region = best.1
        let x = clampedX(ideal: region.midX - size.width / 2, width: min(size.width, region.width), usable: region, margin: 0)
        let y = clampedY(ideal: region.midY - size.height / 2, height: min(size.height, region.height), usable: region, margin: 0)
        return CGRect(x: x, y: y, width: min(size.width, region.width), height: min(size.height, region.height))
    }

    private static func scrollOffsetToMakeRoom(
        highlight: CGRect,
        cardHeight: CGFloat,
        metrics: TourLayoutMetrics,
        usable: CGRect
    ) -> CGFloat {
        // Prefer creating space below the highlight by scrolling it upward.
        let neededBelow = cardHeight + metrics.minimumGap + metrics.cardMargin
        let spaceBelow = usable.maxY - highlight.maxY
        if spaceBelow >= neededBelow {
            return 0
        }
        let deficit = neededBelow - spaceBelow
        // Also keep highlight inside usable after scroll.
        return deficit
    }
}
