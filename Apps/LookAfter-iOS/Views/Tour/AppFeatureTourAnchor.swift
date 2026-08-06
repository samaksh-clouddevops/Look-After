import SwiftUI

/// Preference payload for tour anchor discovery (global frame + corner radius).
struct AppFeatureTourAnchorPayload: Equatable {
    var frame: CGRect
    var cornerRadius: CGFloat
}

extension View {
    /// Registers this view as a guided-tour target. Frames are reported in global coordinates.
    func featureTourAnchor(_ id: AppFeatureTourAnchorID, cornerRadius: CGFloat = 16) -> some View {
        background {
            FeatureTourAnchorFrameReader(id: id, cornerRadius: cornerRadius)
        }
        .anchorPreference(key: TourScrollAnchorPreferenceKey.self, value: .bounds) { anchor in
            [id.rawValue: anchor]
        }
    }
}

/// Reports anchor geometry directly to the tour coordinator — avoids preference churn per frame.
private struct FeatureTourAnchorFrameReader: View {
    @EnvironmentObject private var tour: AppFeatureTourCoordinator

    let id: AppFeatureTourAnchorID
    let cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .onGeometryChange(for: AppFeatureTourAnchorPayload.self) { proxy in
                AppFeatureTourAnchorPayload(
                    frame: proxy.frame(in: .global),
                    cornerRadius: cornerRadius
                )
            } action: { newPayload in
                guard newPayload.frame.width > 0, newPayload.frame.height > 0 else {
                    tour.clearAnchor(id)
                    return
                }
                tour.reportAnchor(id: id, payload: newPayload)
            }
            .onDisappear {
                tour.clearAnchor(id)
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
