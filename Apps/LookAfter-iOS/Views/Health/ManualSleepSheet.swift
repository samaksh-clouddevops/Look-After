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
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Text("No sleep data from last night")
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)

                Text("Apple Health didn't record your sleep. How did you actually sleep? We'll use this to pace your day.")
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Last night's sleep")
                    .font(.dsCaption(weight: .semibold))
                    .foregroundColor(DesignSystem.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .padding(.top, DesignSystem.spacingXXS)

                HStack(spacing: DesignSystem.spacingXS) {
                    ForEach(ManualSleepRating.allCases) { rating in
                        ratingButton(rating)
                    }
                }

                if let selected {
                    Text("\(selected.label) — we'll adjust your plan accordingly.")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .accessibilityLabel("\(selected.label) selected")
                }

                Button {
                    guard let selected else { return }
                    onSubmit(selected)
                    dismiss()
                } label: {
                    Text("Save sleep")
                        .font(.dsCaption(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DesignSystem.minTouchTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(LookAfterChrome.accentTint)
                .disabled(selected == nil)
                .opacity(selected == nil ? 0.45 : 1)

                Spacer(minLength: 0)
            }
            .padding(DesignSystem.spacingLG)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DesignSystem.backgroundPrimary.ignoresSafeArea())
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                Image(systemName: rating.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? DesignSystem.accentPrimary : DesignSystem.textSecondary)
                    .frame(height: 28)
                Text(rating.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? DesignSystem.accentPrimary : DesignSystem.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .fill(isSelected ? DesignSystem.accentPrimary.opacity(0.15) : DesignSystem.contentSurfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .stroke(isSelected ? DesignSystem.accentPrimary : DesignSystem.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rating.label) sleep")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
