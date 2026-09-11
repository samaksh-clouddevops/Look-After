import SwiftUI
import LookAfterCore

enum LookAfterTab: Int, CaseIterable, Identifiable {
    case briefing
    case today
    case review
    case brain
    case you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .briefing: return LookAfterL10n.tabBriefing
        case .today: return LookAfterL10n.tabToday
        case .review: return LookAfterL10n.tabReview
        case .brain: return LookAfterL10n.tabBrain
        case .you: return LookAfterL10n.tabYou
        }
    }

    var icon: String {
        switch self {
        case .briefing: return "doc.text"
        case .today: return "calendar"
        case .review: return "chart.bar"
        case .brain: return "brain.head.profile"
        case .you: return "person"
        }
    }

    var selectedIcon: String {
        switch self {
        case .briefing: return "doc.text.fill"
        case .today: return "calendar"
        case .review: return "chart.bar.fill"
        case .brain: return "brain.head.profile"
        case .you: return "person.fill"
        }
    }
}

/// Stable ID for Capture chrome morph (tab button → sheet zoom).
enum LookAfterCaptureMorph {
    static let sourceID = "lookAfter.capture"
}

/// Applies Capture zoom only when Reduce Motion is off.
struct CaptureSheetZoomModifier: ViewModifier {
    let reduceMotion: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .navigationTransition(.zoom(sourceID: LookAfterCaptureMorph.sourceID, in: namespace))
        }
    }
}

/// Tags Capture chrome for glass/zoom morph; skipped under Reduce Motion.
private struct CaptureMorphSourceModifier: ViewModifier {
    let reduceMotion: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .glassEffectID(LookAfterCaptureMorph.sourceID, in: namespace)
                .matchedTransitionSource(id: LookAfterCaptureMorph.sourceID, in: namespace)
        }
    }
}

/// Sheet / navigation zoom morph helpers (task detail F3; Capture uses dedicated modifiers above).
extension View {
    @ViewBuilder
    func lookAfterZoomSource(
        id: some Hashable,
        in namespace: Namespace.ID,
        enabled: Bool
    ) -> some View {
        if enabled {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func lookAfterZoomDestination(
        sourceID: some Hashable,
        in namespace: Namespace.ID,
        enabled: Bool
    ) -> some View {
        if enabled {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}

/// Root tab chrome — compact Liquid Glass bar flush to the home indicator.
/// Path-to-10 Wave F: 4 labeled tabs + quiet Capture FAB; Review lives under You.
struct LookAfterBottomNav: View {
    @EnvironmentObject private var featureTour: AppFeatureTourCoordinator
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: LookAfterTab
    var captureMorphNamespace: Namespace.ID
    var onCapture: () -> Void
    @State private var captureBounceToken = 0
    @State private var tabBounceTokens: [LookAfterTab: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.briefing)
            tabButton(.today)
            captureButton
            tabButton(.brain)
            tabButton(.you)
        }
        .padding(.horizontal, DesignSystem.spacingXXS)
        .padding(.top, DesignSystem.spacingXXS)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
        .background {
            LookAfterTabBarPlate(reduceTransparency: reduceTransparency)
        }
        .background {
            TourTabBarFrameReader()
        }
        .accessibilityElement(children: .contain)
    }

    /// Capture is not a `LookAfterTab` — never gets selected lime tint; only `LACaptureFAB` quiet chrome.
    private var captureButton: some View {
        LACaptureFAB(
            bounceToken: captureBounceToken,
            reduceMotion: reduceMotion,
            action: {
                HapticManager.impact(.light)
                if !reduceMotion {
                    captureBounceToken &+= 1
                }
                onCapture()
            }
        )
        .modifier(CaptureMorphSourceModifier(
            reduceMotion: reduceMotion,
            namespace: captureMorphNamespace
        ))
        .accessibilityIdentifier("tab-capture")
        .accessibilityLabel(LookAfterL10n.tabCapture)
        .featureTourAnchor(.tabCapture, cornerRadius: LAChromeMetrics.fabDiameter / 2)
    }

    private func tabButton(_ tab: LookAfterTab) -> some View {
        let isSelected = selection == tab
        let bounceToken = tabBounceTokens[tab, default: 0]

        return Button(action: {
            HapticManager.impact(.light)
            let signpost = PerformanceSignposts.beginTabTransition()
            withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                selection = tab
            }
            if !reduceMotion {
                tabBounceTokens[tab, default: 0] &+= 1
            }
            PerformanceSignposts.endTabTransition(signpost)
        }, label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: LAChromeMetrics.iconPointSize, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)
                    .modifier(TabIconBounceModifier(token: bounceToken, reduceMotion: reduceMotion))
                Text(tab.title)
                    .font(.dsTabLabel(weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            // Selected language is lime tint on icon+label only — not applied to Capture.
            .foregroundStyle(isSelected ? DesignSystem.accentPrimary : DesignSystem.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DesignSystem.minTouchTarget)
            .contentShape(Rectangle())
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
        case .review: return .tabReview
        case .brain: return .tabBrain
        case .you: return .tabYou
        }
    }
}

private struct TabIconBounceModifier: ViewModifier {
    let token: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.bounce, value: token)
        }
    }
}

/// Fills the home-indicator region so the bar reads as edge-docked.
private struct LookAfterTabBarPlate: View {
    let reduceTransparency: Bool

    var body: some View {
        Group {
            if reduceTransparency {
                DesignSystem.backgroundSecondary
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(DesignSystem.divider)
                            .frame(height: 1)
                    }
            } else {
                Color.clear
                    .glassEffect(.regular, in: .rect)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Reports tab bar frame directly to the tour coordinator.
private struct TourTabBarFrameReader: View {
    @EnvironmentObject private var tour: AppFeatureTourCoordinator

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                tour.reportTabBarFrame(newFrame)
            }
    }
}
