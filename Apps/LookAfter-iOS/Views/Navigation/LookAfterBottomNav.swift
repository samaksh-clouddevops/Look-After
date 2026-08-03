import SwiftUI
import LookAfterCore

enum LookAfterTab: Int, CaseIterable, Identifiable {
    case briefing
    case timeline
    case work
    case brain
    case you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .briefing: return "Briefing"
        case .timeline: return "Timeline"
        case .work: return "Work"
        case .brain: return "Brain"
        case .you: return "You"
        }
    }

    var icon: String {
        switch self {
        case .briefing: return "house"
        case .timeline: return "calendar"
        case .work: return "rectangle.stack"
        case .brain: return "sparkles"
        case .you: return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .briefing: return "house.fill"
        case .timeline: return "calendar"
        case .work: return "rectangle.stack.fill"
        case .brain: return "sparkles"
        case .you: return "person.fill"
        }
    }
}

struct LookAfterBottomNav: View {
    @Binding var selection: LookAfterTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LookAfterTab.allCases) { tab in
                tabButton(tab)
            }
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

    private func tabButton(_ tab: LookAfterTab) -> some View {
        let isSelected = selection == tab

        return Button {
            HapticManager.impact(.light)
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = tab
            }
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
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
