import SwiftUI

/// Preference payload for tour anchor discovery (global frame + corner radius).
struct AppFeatureTourAnchorPayload: Equatable {
    var frame: CGRect
    var cornerRadius: CGFloat
}

struct AppFeatureTourFramePreferenceKey: PreferenceKey {
    static var defaultValue: [AppFeatureTourAnchorID: AppFeatureTourAnchorPayload] = [:]

    static func reduce(
        value: inout [AppFeatureTourAnchorID: AppFeatureTourAnchorPayload],
        nextValue: () -> [AppFeatureTourAnchorID: AppFeatureTourAnchorPayload]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Registers this view as a guided-tour target. Frames are reported in global coordinates.
    func featureTourAnchor(_ id: AppFeatureTourAnchorID, cornerRadius: CGFloat = 16) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: AppFeatureTourFramePreferenceKey.self,
                    value: [
                        id: AppFeatureTourAnchorPayload(
                            frame: geo.frame(in: .global),
                            cornerRadius: cornerRadius
                        )
                    ]
                )
            }
        )
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
