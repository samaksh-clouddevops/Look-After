import SwiftUI

extension View {
    /// Registers this view as a guided-tour target. Frames are reported in global coordinates.
    func featureTourAnchor(_ id: AppFeatureTourAnchorID, cornerRadius: CGFloat = 16) -> some View {
        modifier(FeatureTourAnchorModifier(id: id, cornerRadius: cornerRadius))
    }
}

/// Reports tour anchor geometry directly to the coordinator (avoids preference double-write per frame).
private struct FeatureTourAnchorModifier: ViewModifier {
    let id: AppFeatureTourAnchorID
    let cornerRadius: CGFloat

    @EnvironmentObject private var featureTour: AppFeatureTourCoordinator

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                guard featureTour.isActive else { return }
                featureTour.reportAnchorFrame(id, frame: newFrame, cornerRadius: cornerRadius)
            }
            .anchorPreference(key: TourScrollAnchorPreferenceKey.self, value: .bounds) { anchor in
                [id.rawValue: anchor]
            }
    }
}

/// Optional scroll-target registry for ScrollViewReader consumers.
struct TourScrollAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
