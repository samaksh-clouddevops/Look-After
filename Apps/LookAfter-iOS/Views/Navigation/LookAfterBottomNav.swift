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
        case .briefing: return "house"
        case .today: return "calendar"
        case .brain: return "sparkles"
        case .you: return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .briefing: return "house.fill"
        case .today: return "calendar"
        case .brain: return "sparkles"
        case .you: return "person.fill"
        }
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
        .accessibilityElement(children: .contain)
    }

    private var captureButton: some View {
        Button {
            HapticManager.impact(.medium)
            onCapture()
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(DesignSystem.accentOnPrimary, DesignSystem.accentPrimary)
                .frame(maxWidth: .infinity)
                .offset(y: -8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-capture")
        .accessibilityLabel("Capture")
    }

    private func tabButton(_ tab: LookAfterTab) -> some View {
        let isSelected = selection == tab

        return Button {
            HapticManager.impact(.light)
            let signpost = PerformanceSignposts.beginTabTransition()
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = tab
            }
            PerformanceSignposts.endTabTransition(signpost)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? DesignSystem.accentPrimary : DesignSystem.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(tab.title.lowercased())")
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
