import CoreGraphics
import Foundation

// MARK: - Placement

/// Preferred side for a tour explanation card relative to a highlight.
public enum TourCardSide: String, Sendable, CaseIterable, Equatable {
    case above
    case below
    case left
    case right
    case center
    case floating
}

/// Arrow orientation from card toward the highlighted target.
public enum TourArrowEdge: String, Sendable, Equatable {
    case top
    case bottom
    case left
    case right
    case none
}

// MARK: - Layout inputs

/// Snapshot of screen chrome and obstacles the tour must respect.
public struct TourLayoutMetrics: Sendable, Equatable {
    public var screenBounds: CGRect
    public var safeAreaInsets: TourEdgeInsets
    public var keyboardFrame: CGRect
    public var navigationBarFrame: CGRect
    public var tabBarFrame: CGRect
    public var bottomSheetFrame: CGRect
    public var floatingObstacleFrames: [CGRect]
    public var cardSize: CGSize
    public var cardMargin: CGFloat
    public var highlightPadding: CGFloat
    public var minimumGap: CGFloat
    /// Vertical/horizontal arrow protrusion beyond the card rect.
    public var arrowLength: CGFloat
    /// Extra inset below the safe area for Dynamic Island / status bar breathing room.
    public var topObstacleInset: CGFloat
    public var preferredSides: [TourCardSide]

    public init(
        screenBounds: CGRect,
        safeAreaInsets: TourEdgeInsets = .zero,
        keyboardFrame: CGRect = .null,
        navigationBarFrame: CGRect = .null,
        tabBarFrame: CGRect = .null,
        bottomSheetFrame: CGRect = .null,
        floatingObstacleFrames: [CGRect] = [],
        cardSize: CGSize = CGSize(width: 320, height: 220),
        cardMargin: CGFloat = 16,
        highlightPadding: CGFloat = 10,
        minimumGap: CGFloat = 12,
        arrowLength: CGFloat = 10,
        topObstacleInset: CGFloat = 0,
        preferredSides: [TourCardSide] = [.above, .below, .left, .right, .center, .floating]
    ) {
        self.screenBounds = screenBounds
        self.safeAreaInsets = safeAreaInsets
        self.keyboardFrame = keyboardFrame
        self.navigationBarFrame = navigationBarFrame
        self.tabBarFrame = tabBarFrame
        self.bottomSheetFrame = bottomSheetFrame
        self.floatingObstacleFrames = floatingObstacleFrames
        self.cardSize = cardSize
        self.cardMargin = cardMargin
        self.highlightPadding = highlightPadding
        self.minimumGap = minimumGap
        self.arrowLength = arrowLength
        self.topObstacleInset = topObstacleInset
        self.preferredSides = preferredSides
    }

    /// Usable content area after safe area, Dynamic Island clearance, keyboard, tab bar, and bottom sheet.
    public var usableBounds: CGRect {
        var rect = screenBounds.inset(by: safeAreaInsets)
        if topObstacleInset > 0 {
            rect.origin.y += topObstacleInset
            rect.size.height = max(0, rect.size.height - topObstacleInset)
        }
        if keyboardFrame.isValidObstacle {
            let topOfKeyboard = keyboardFrame.minY
            if topOfKeyboard < rect.maxY {
                rect.size.height = max(0, topOfKeyboard - rect.minY - cardMargin)
            }
        }
        if tabBarFrame.isValidObstacle {
            let topOfTab = tabBarFrame.minY
            if topOfTab < rect.maxY {
                rect.size.height = min(rect.height, max(0, topOfTab - rect.minY - cardMargin))
            }
        }
        if bottomSheetFrame.isValidObstacle {
            let topOfSheet = bottomSheetFrame.minY
            if topOfSheet < rect.maxY {
                rect.size.height = min(rect.height, max(0, topOfSheet - rect.minY - cardMargin))
            }
        }
        if navigationBarFrame.isValidObstacle {
            let bottomOfNav = navigationBarFrame.maxY
            if bottomOfNav > rect.minY {
                let delta = bottomOfNav - rect.minY + cardMargin
                rect.origin.y += delta
                rect.size.height = max(0, rect.height - delta)
            }
        }
        return rect
    }
}

public struct TourEdgeInsets: Sendable, Equatable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public static let zero = TourEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

// MARK: - Layout result

public struct TourLayoutProposal: Sendable, Equatable {
    public var cardFrame: CGRect
    public var highlightFrame: CGRect
    public var side: TourCardSide
    public var arrowEdge: TourArrowEdge
    public var arrowTip: CGPoint
    public var needsScroll: Bool
    /// Positive = scroll content up so target moves up; negative = opposite.
    public var suggestedScrollOffset: CGFloat
    public var score: CGFloat

    public init(
        cardFrame: CGRect,
        highlightFrame: CGRect,
        side: TourCardSide,
        arrowEdge: TourArrowEdge,
        arrowTip: CGPoint,
        needsScroll: Bool = false,
        suggestedScrollOffset: CGFloat = 0,
        score: CGFloat = 0
    ) {
        self.cardFrame = cardFrame
        self.highlightFrame = highlightFrame
        self.side = side
        self.arrowEdge = arrowEdge
        self.arrowTip = arrowTip
        self.needsScroll = needsScroll
        self.suggestedScrollOffset = suggestedScrollOffset
        self.score = score
    }
}

// MARK: - CGRect helpers

public extension CGRect {
    var isValidObstacle: Bool {
        !isNull && !isInfinite && width > 0.5 && height > 0.5
    }

    func inset(by insets: TourEdgeInsets) -> CGRect {
        CGRect(
            x: minX + insets.left,
            y: minY + insets.top,
            width: max(0, width - insets.left - insets.right),
            height: max(0, height - insets.top - insets.bottom)
        )
    }

    func expanded(by amount: CGFloat) -> CGRect {
        insetBy(dx: -amount, dy: -amount)
    }

    /// Intersection area; 0 if no overlap.
    func intersectionArea(with other: CGRect) -> CGFloat {
        let i = intersection(other)
        guard !i.isNull else { return 0 }
        return i.width * i.height
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
