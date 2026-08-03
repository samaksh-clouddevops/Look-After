import SwiftUI

/// Contextual opening progress — never a generic spinner alone.
public struct MeaningfulProgressView: View {
    let heading: String
    let steps: [String]
    let progress: Double

    public init(heading: String, steps: [String], progress: Double) {
        self.heading = heading
        self.steps = steps
        self.progress = min(max(progress, 0), 1)
    }

    private var completedCount: Int {
        guard !steps.isEmpty else { return 0 }
        if progress >= 1 { return steps.count }
        return min(steps.count, Int(floor(progress * Double(steps.count))))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(heading)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 10) {
                        Image(systemName: index < completedCount ? "checkmark" : "circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(index < completedCount ? DesignSystem.accentPrimary : DesignSystem.textMuted.opacity(0.35))
                            .frame(width: 18)

                        Text(step)
                            .font(.system(size: 17, weight: index < completedCount ? .medium : .regular))
                            .foregroundColor(index < completedCount ? DesignSystem.textPrimary : DesignSystem.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 36)
    }
}
