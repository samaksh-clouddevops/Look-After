import SwiftUI
import LookAfterCore

/// Prompts for self-reported sleep when Apple Health has no overnight data.
struct ManualSleepSheet: View {
    let onSubmit: (ManualSleepRating) -> Void
    let onSkip: () -> Void

    @State private var selected: ManualSleepRating?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                    Text("No sleep data from last night")
                        .font(.dsHeadline())
                        .foregroundColor(DesignSystem.textPrimary)

                    Text("Apple Health didn't record your sleep. How did you actually sleep? We'll use this to pace your day.")
                        .font(.dsBody())
                        .foregroundColor(DesignSystem.textSecondary)
                        .dsPrimaryText(lineLimit: 4)

                    VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                        Text("Last night's sleep")
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)
                            .tracking(0.4)

                        HStack(spacing: DesignSystem.spacingSM) {
                            ForEach(ManualSleepRating.allCases) { rating in
                                ratingButton(rating)
                            }
                        }
                    }

                    if let selected {
                        Text("\(selected.emoji) \(selected.label) — we'll adjust your plan accordingly.")
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                    }

                    Button {
                        guard let selected else { return }
                        onSubmit(selected)
                        dismiss()
                    } label: {
                        Text("Save sleep")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil)

                    Spacer(minLength: 0)
                }
                .padding(DesignSystem.spacingLG)
            }
            .navigationTitle("How did you sleep?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        onSkip()
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("screen-manual-sleep")
        .interactiveDismissDisabled()
    }

    private func ratingButton(_ rating: ManualSleepRating) -> some View {
        let isSelected = selected == rating
        return Button {
            selected = rating
            HapticManager.impact(.light)
        } label: {
            VStack(spacing: 6) {
                Text(rating.emoji)
                    .font(.system(size: 28))
                Text(rating.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? DesignSystem.accentPrimary : DesignSystem.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .fill(isSelected ? DesignSystem.accentPrimary.opacity(0.15) : DesignSystem.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .stroke(isSelected ? DesignSystem.accentPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rating.label) sleep")
    }
}
