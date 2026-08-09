import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// UserDefaults key — set after the first successful vertical schedule drag.
enum TimelineDragHint {
    static let dismissedKey = "timelineDragHintDismissed"
}

/// Live clock preview shown in the left time rail while dragging a timeline block.
struct TimelineDragTimeMeter: View {
    let proposedStart: Date?
    let durationMinutes: Int?
    let anchorY: CGFloat?
    let timeColumnWidth: CGFloat

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var labelText: String? {
        guard let proposedStart else { return nil }
        guard let durationMinutes, durationMinutes > 0 else {
            return Self.timeFormatter.string(from: proposedStart)
        }
        let end = proposedStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return ScheduleTimeFormatting.rangeLabel(from: proposedStart, to: end)
    }

    var body: some View {
        GeometryReader { proxy in
            if let labelText, let anchorY {
                let clampedY = min(max(anchorY, 0), proxy.size.height)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(DesignSystem.accentPrimary.opacity(0.35))
                        .frame(height: 1)
                        .offset(y: clampedY)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 0) {
                        Text(labelText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DesignSystem.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DesignSystem.accentPrimary.opacity(0.22))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(DesignSystem.accentPrimary.opacity(0.55), lineWidth: 1)
                                    )
                            )
                            .offset(y: clampedY - 12)
                            .frame(width: timeColumnWidth, alignment: .trailing)

                        Spacer(minLength: 0)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityLabel("Drop at \(labelText)")
            }
        }
    }
}
