import SwiftUI

/// Determinate progress bar without GeometryReader layout side-effects.
public struct ProgressBarView: View {
    let progress: Double
    var height: CGFloat
    var tint: AnyShapeStyle

    public init(
        progress: Double,
        height: CGFloat = 4,
        tint: AnyShapeStyle = AnyShapeStyle(DesignSystem.accentGradient)
    ) {
        self.progress = progress
        self.height = height
        self.tint = tint
    }

    public var body: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.1))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: max(0, geo.size.width * min(max(progress, 0), 1)))
                }
            }
            .frame(height: height)
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}
