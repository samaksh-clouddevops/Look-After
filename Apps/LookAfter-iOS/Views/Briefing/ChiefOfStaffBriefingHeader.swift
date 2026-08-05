import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Progressive disclosure top of Briefing:
/// 1) AI narrative (SF Pro Display ~24)  2) Deterministic snapshot chips  3) timeline below.
/// Read-only — no chat / mic. Haptic fade on text reveal.
struct ChiefOfStaffBriefingHeader: View {
    let narrative: String
    let chips: [BriefingSnapshotChip]
    let isLoading: Bool
    var fromCache: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var lastNarrative = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            Text(displayNarrative)
                .font(BriefingTypeScale.headerFont) // 27pt = floor(17 × φ)
                .foregroundColor(DesignSystem.textPrimary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(8)
                .opacity(revealed ? 1 : 0.35)
                .accessibilityIdentifier("briefing-chief-narrative")
                .accessibilityLabel(displayNarrative)

            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.spacingSM) {
                        ForEach(chips) { chip in
                            SnapshotChipView(chip: chip)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("briefing-snapshot-chips")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            animateReveal(for: narrative)
        }
        .onChange(of: narrative) { _, newValue in
            animateReveal(for: newValue)
        }
    }

    private var displayNarrative: String {
        if !narrative.isEmpty { return narrative }
        if isLoading { return "Reading your day…" }
        return "Your day is taking shape."
    }

    private func animateReveal(for text: String) {
        guard text != lastNarrative, !text.isEmpty else {
            revealed = true
            return
        }
        lastNarrative = text
        if reduceMotion {
            revealed = true
            return
        }
        revealed = false
        // Soft selection haptic — system "finished thinking".
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        withAnimation(.easeOut(duration: 0.45)) {
            revealed = true
        }
    }
}

private struct SnapshotChipView: View {
    let chip: BriefingSnapshotChip

    var body: some View {
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
        .background(
            Capsule(style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(DesignSystem.border.opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chip.label) \(chip.value)")
    }
}
