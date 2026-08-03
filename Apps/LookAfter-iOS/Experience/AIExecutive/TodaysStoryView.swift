import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Today's Story — narrative typography, not a timeline.
struct TodaysStoryView: View {
    @Environment(\.dismiss) private var dismiss

    let story: TodaysStory

    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack {
            CinematicBackground(accentIntensity: 0.25)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ScrollOffsetReporter()

                    narrativeOpening
                        .padding(.top, 56)
                        .padding(.bottom, 64)

                    narrativeBody
                        .padding(.horizontal, 28)
                        .padding(.bottom, 80)
                }
            }
            .coordinateSpace(name: "cinematicScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(DesignSystem.textMuted)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)
                Spacer()
            }
        }
        .accessibilityIdentifier("screen-todays-story")
    }

    private var narrativeOpening: some View {
        VStack(spacing: 24) {
            Text("Your Day")
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textMuted)

            Text(story.greeting)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .scaleEffect(1 - min(max(-scrollOffset, 0) / 600, 0) * 0.1)
        }
    }

    private var narrativeBody: some View {
        VStack(spacing: 56) {
            ForEach(story.segments) { segment in
                NarrativeBeat(period: segment.periodLabel, activity: segment.title)
            }
        }
    }
}
