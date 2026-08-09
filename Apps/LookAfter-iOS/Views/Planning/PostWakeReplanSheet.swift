import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Captures wake time and starts a post-wake contextual replan.
struct PostWakeReplanSheet: View {
    let suggestedWakeTime: Date?
    let onSubmit: (Date) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var wakeTime: Date
    @State private var isSubmitting = false

    init(suggestedWakeTime: Date?, onSubmit: @escaping (Date) async -> Void) {
        self.suggestedWakeTime = suggestedWakeTime
        self.onSubmit = onSubmit
        _wakeTime = State(initialValue: suggestedWakeTime ?? Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                    Text("When did you wake up?")
                        .font(.dsHeadline())
                        .foregroundColor(DesignSystem.textPrimary)

                    Text("I'll figure out what you missed and reshape the rest of today.")
                        .font(.dsBody())
                        .foregroundColor(DesignSystem.textSecondary)

                    DatePicker(
                        "Wake time",
                        selection: $wakeTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                    Button {
                        Task {
                            isSubmitting = true
                            await onSubmit(wakeTime)
                            isSubmitting = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text("Replan my day")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)

                    Spacer(minLength: 0)
                }
                .padding(DesignSystem.spacingLG)
            }
            .navigationTitle("I just woke up")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("screen-post-wake-replan")
    }
}
