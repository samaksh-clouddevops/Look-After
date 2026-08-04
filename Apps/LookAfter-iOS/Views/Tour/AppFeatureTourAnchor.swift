import SwiftUI

struct AppFeatureTourFramePreferenceKey: PreferenceKey {
    static var defaultValue: [AppFeatureTourAnchorID: CGRect] = [:]

    static func reduce(value: inout [AppFeatureTourAnchorID: CGRect], nextValue: () -> [AppFeatureTourAnchorID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func featureTourAnchor(_ id: AppFeatureTourAnchorID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: AppFeatureTourFramePreferenceKey.self,
                    value: [id: geo.frame(in: .global)]
                )
            }
        )
    }
}
