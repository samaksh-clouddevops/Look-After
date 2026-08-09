import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Captures departure time + duration and starts a going-out contextual replan.
struct GoingOutSheet: View {
    let onSubmit: (Date, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var departureTime: Date
    @State private var durationMinutes = 120
    @State private var isSubmitting = false

    private let durationOptions = [30, 60, 90, 120, 180, 240]

    init(onSubmit: @escaping (Date, Int) async -> Void) {
        self.onSubmit = onSubmit
        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        let roundedMinutes = ((minute + 29) / 30) * 30
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        components.minute = 0
        components.second = 0
        let base = calendar.date(from: components) ?? now
        let departure = calendar.date(byAdding: .minute, value: roundedMinutes, to: base) ?? now
        _departureTime = State(initialValue: departure)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                    Text("When are you heading out?")
                        .font(.dsHeadline())
                        .foregroundColor(DesignSystem.textPrimary)

                    Text("I'll pack what fits before you leave and defer the rest.")
                        .font(.dsBody())
                        .foregroundColor(DesignSystem.textSecondary)

                    DatePicker(
                        "Departure",
                        selection: $departureTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.compact)

                    Text("How long will you be out?")
                        .font(.dsBody(weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignSystem.spacingSM) {
                            ForEach(durationOptions, id: \.self) { minutes in
                                Button {
                                    durationMinutes = minutes
                                } label: {
                                    Text(durationLabel(minutes))
                                        .font(.dsCaption(weight: .semibold))
                                        .foregroundColor(durationMinutes == minutes ? .white : DesignSystem.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule().fill(
                                                durationMinutes == minutes
                                                    ? DesignSystem.accentPrimary
                                                    : DesignSystem.backgroundElevated
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Text("Back around \(returnLabel)")
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textMuted)

                    Button {
                        Task {
                            isSubmitting = true
                            await onSubmit(departureTime, durationMinutes)
                            isSubmitting = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text("Replan around outing")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting)

                    Spacer(minLength: 0)
                }
                .padding(DesignSystem.spacingLG)
            }
            .navigationTitle("Going out")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("screen-going-out")
    }

    private var returnLabel: String {
        let end = departureTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return end.formatted(date: .omitted, time: .shortened)
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
