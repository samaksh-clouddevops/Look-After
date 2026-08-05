import SwiftUI
import LookAfterCore

enum LookAfterTab: Int, CaseIterable, Identifiable {
    case briefing
    case today
    case brain
    case you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .briefing: return "Briefing"
        case .today: return "Today"
        case .brain: return "Brain"
        case .you: return "You"
        }
    }

    var icon: String {
        switch self {
        case .briefing: return "doc.text"
        case .today: return "calendar"
        case .brain: return "brain.head.profile"
        case .you: return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .briefing: return "doc.text.fill"
        case .today: return "calendar"
        case .brain: return "brain.head.profile"
        case .you: return "person.fill"
        }
    }
}

struct TourTabBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.isValidObstacle { value = next }
    }
}

struct LookAfterBottomNav: View {
    @Binding var selection: LookAfterTab
    var onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.briefing)
            tabButton(.today)
            captureButton
            tabButton(.brain)
            tabButton(.you)
        }
        .padding(.horizontal, DesignSystem.spacingSM)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            DesignSystem.backgroundSecondary
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DesignSystem.divider)
                        .frame(height: 1)
                }
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TourTabBarFramePreferenceKey.self,
                    value: geo.frame(in: .global)
                )
            }
        )
        .accessibilityElement(children: .contain)
    }

    private var captureButton: some View {
        Button(action: {
            HapticManager.impact(.medium)
            onCapture()
        }, label: {
            Image(systemName: "plus.circle.fill")
                .font(.dsIconLarge())
                .symbolRenderingMode(.palette)
                .foregroundStyle(DesignSystem.accentOnPrimary, DesignSystem.accentPrimary)
                .frame(maxWidth: .infinity)
                .offset(y: -8)
        })
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-capture")
        .accessibilityLabel("Capture")
        .featureTourAnchor(.tabCapture, cornerRadius: 22)
    }

    private func tabButton(_ tab: LookAfterTab) -> some View {
        let isSelected = selection == tab

        return Button(action: {
            HapticManager.impact(.light)
            let signpost = PerformanceSignposts.beginTabTransition()
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = tab
            }
            PerformanceSignposts.endTabTransition(signpost)
        }, label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.dsIcon(weight: isSelected ? .bold : .medium))
                    .symbolRenderingMode(.monochrome)
                Text(tab.title)
                    .textStyleTabLabel(color: isSelected ? DesignSystem.accentPrimary : DesignSystem.textSecondary, active: isSelected)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? DesignSystem.accentPrimary : DesignSystem.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        })
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(tab.title.lowercased())")
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .featureTourAnchor(tourAnchor(for: tab))
    }

    private func tourAnchor(for tab: LookAfterTab) -> AppFeatureTourAnchorID {
        switch tab {
        case .briefing: return .tabBriefing
        case .today: return .tabToday
        case .brain: return .tabBrain
        case .you: return .tabYou
        }
    }
}
