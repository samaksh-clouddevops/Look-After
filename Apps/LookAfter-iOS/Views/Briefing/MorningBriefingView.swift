import SwiftUI
import LookAfterCore
import LookAfterFeatures
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Golden ratio type scale

/// Body 17pt → Header 17 × φ ≈ 27.5 → 27pt (φ = 1.618).
enum BriefingTypeScale {
    static let phi: CGFloat = 1.618
    static let body: CGFloat = 17
    static let header: CGFloat = 27 // floor(17 * 1.618)

    static var headerFont: Font {
        .system(size: header, weight: .medium, design: .default)
    }

    static var bodyFont: Font {
        .system(size: body, weight: .regular, design: .default)
    }

    static var chipFont: Font {
        .system(size: 13, weight: .medium, design: .default)
    }
}

// MARK: - Morning Briefing (read-only)

/// Progressive disclosure: AI narrative (27pt) → deterministic chips → optional timeline slot.
/// No chat input. Soft opacity + selection haptic on reveal.
struct MorningBriefingView: View {
    let narrative: String
    let chips: [BriefingSnapshotChip]
    var isLoading: Bool = false
    var greetingName: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var displayedNarrative = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
            // Top — AI text (golden-ratio header)
            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                if !greetingName.isEmpty {
                    Text(timeGreeting)
                        .font(BriefingTypeScale.chipFont)
                        .foregroundColor(DesignSystem.textSecondary)
                }

                Text(visibleText)
                    .font(BriefingTypeScale.headerFont)
                    .foregroundColor(DesignSystem.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(revealed ? 1 : (isLoading ? 0.4 : 1))
                    .accessibilityIdentifier("morning-briefing-narrative")
                    .accessibilityLabel(visibleText)
            }

            // Middle — deterministic snapshot (LifeState, not LLM)
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.spacingSM) {
                        ForEach(chips) { chip in
                            chipView(chip)
                        }
                    }
                }
                .accessibilityIdentifier("morning-briefing-chips")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { present(narrative) }
        .onChange(of: narrative) { _, newValue in
            present(newValue)
        }
    }

    private var visibleText: String {
        if !displayedNarrative.isEmpty { return displayedNarrative }
        if isLoading { return "Reading your day…" }
        return "Your day is taking shape."
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part: String
        switch hour {
        case 5..<12: part = "Good morning"
        case 12..<17: part = "Good afternoon"
        default: part = "Good evening"
        }
        return "\(part), \(greetingName)"
    }

    private func chipView(_ chip: BriefingSnapshotChip) -> some View {
        HStack(spacing: 6) {
            Image(systemName: chip.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.accentPrimary)
            Text(chip.label)
                .font(BriefingTypeScale.chipFont)
                .foregroundColor(DesignSystem.textSecondary)
            Text(chip.value)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(DesignSystem.backgroundSecondary))
        .overlay(Capsule(style: .continuous).stroke(DesignSystem.border.opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chip.label) \(chip.value)")
    }

    private func present(_ text: String) {
        guard text != displayedNarrative else {
            revealed = true
            return
        }
        if reduceMotion {
            displayedNarrative = text
            revealed = true
            return
        }
        revealed = false
        displayedNarrative = text
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        withAnimation(.easeOut(duration: 0.42)) {
            revealed = true
        }
    }
}

// MARK: - Preview mocks

#if DEBUG
enum MorningBriefingPreviewData {
    /// Phase-spec mock: sabotage + park + semantic supersede + decay/expire tallies.
    static let mockRouterPayload = BriefingRouterPayload(
        energyState: "Recovery",
        anchoredCommitmentsCount: 2,
        fluidHoursAvailable: 2.0,
        systemActions: [
            "Triggered a Sabotage Auction to enforce a 90-minute recovery block.",
            "Parked 2 flexible tasks to resolve afternoon crowding.",
            "Superseded yesterday's uncompleted workout to prevent double-booking today."
        ],
        decayedTaskCount: 1,
        supersededTaskCount: 1,
        expiredTaskCount: 1
    )

    static let mockNarrative = """
    Energy is in recovery with two anchors still holding the day and about two hours of fluid time. \
    Overnight a Sabotage Auction locked ninety minutes for rest, and two flexible blocks were parked to clear the afternoon. \
    Yesterday's missed workout was dropped because today already has one — no double session. \
    One parked item is past two weeks; review or bulk-discard when ready.
    """

    static var mockChips: [BriefingSnapshotChip] {
        mockRouterPayload.snapshotChips()
    }
}

#Preview("Morning Briefing — complex mutations") {
    ScrollView {
        MorningBriefingView(
            narrative: MorningBriefingPreviewData.mockNarrative,
            chips: MorningBriefingPreviewData.mockChips,
            isLoading: false,
            greetingName: "Alex"
        )
        .padding(DesignSystem.screenHorizontal)
    }
    .background(DesignSystem.backgroundPrimary)
}

#Preview("Morning Briefing — loading") {
    MorningBriefingView(
        narrative: "",
        chips: MorningBriefingPreviewData.mockChips,
        isLoading: true,
        greetingName: "Alex"
    )
    .padding()
    .background(DesignSystem.backgroundPrimary)
}
#endif
