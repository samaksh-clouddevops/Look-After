import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Synchronously disables the enclosing `UIScrollView` while timeline blocks are lifted/dragged.
/// SwiftUI `.scrollDisabled()` alone is one frame too late — UIScrollView wins the pan first.
public struct ScrollViewScrollLockModifier: ViewModifier {
    let isLocked: Bool

    public init(isLocked: Bool) {
        self.isLocked = isLocked
    }

    public func body(content: Content) -> some View {
        #if os(iOS)
        content.background(ScrollViewScrollLockRepresentable(isLocked: isLocked))
        #else
        content
        #endif
    }
}

public extension View {
    func scrollViewScrollLock(_ isLocked: Bool) -> some View {
        modifier(ScrollViewScrollLockModifier(isLocked: isLocked))
    }
}

#if os(iOS)
private struct ScrollViewScrollLockRepresentable: UIViewRepresentable {
    let isLocked: Bool

    func makeUIView(context: Context) -> ScrollLockAnchorView {
        ScrollLockAnchorView()
    }

    func updateUIView(_ uiView: ScrollLockAnchorView, context: Context) {
        uiView.setLocked(isLocked)
    }
}

private final class ScrollLockAnchorView: UIView {
    private weak var cachedScrollView: UIScrollView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        cachedScrollView = findEnclosingScrollView()
    }

    func setLocked(_ locked: Bool) {
        if cachedScrollView == nil {
            cachedScrollView = findEnclosingScrollView()
        }
        cachedScrollView?.isScrollEnabled = !locked
        cachedScrollView?.panGestureRecognizer.isEnabled = !locked
    }

    private func findEnclosingScrollView() -> UIScrollView? {
        var candidate: UIView? = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }
}
#endif
