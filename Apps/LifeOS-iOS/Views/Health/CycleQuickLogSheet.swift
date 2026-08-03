import SwiftUI
import LifeOSCore
import LifeOSFeatures

struct CycleQuickLogSheet: View {
    @ObservedObject var viewModel: CycleDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var flow: CycleFlowLevel = .none
    @State private var selectedSymptoms: Set<String> = []
    @State private var energy: Double = 3
    @State private var mood = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Quick check-in")
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textSecondary)

                    flowSection
                    symptomSection
                    energySection

                    TextField("Mood (optional)", text: $mood)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

                    Text(UserFacingCopy.medicalDisclaimerWithProvider)
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.textMuted)
                }
                .padding()
            }
            .background(PremiumBackground())
            .navigationTitle("Cycle log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var flowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Flow")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
            FlowLayout(spacing: 8) {
                ForEach(CycleFlowLevel.allCases, id: \.self) { level in
                    Button {
                        flow = level
                    } label: {
                        Text(level.displayLabel)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(flow == level ? DesignSystem.accentPrimary.opacity(0.25) : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var symptomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symptoms")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
            FlowLayout(spacing: 8) {
                ForEach(CycleSymptomCatalog.common, id: \.self) { symptom in
                    Button {
                        if selectedSymptoms.contains(symptom) {
                            selectedSymptoms.remove(symptom)
                        } else {
                            selectedSymptoms.insert(symptom)
                        }
                    } label: {
                        Text(symptom)
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selectedSymptoms.contains(symptom) ? DesignSystem.accentPrimary.opacity(0.2) : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Energy: \(Int(energy))/5")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
            Slider(value: $energy, in: 1...5, step: 1)
                .tint(DesignSystem.accentPrimary)
        }
    }

    private func save() {
        let log = CycleDayLog(
            day: Date(),
            flow: flow == .none ? nil : flow,
            symptoms: Array(selectedSymptoms).sorted(),
            mood: mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : mood,
            energy: Int(energy),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            source: .manual
        )
        viewModel.saveLog(log)
    }
}

/// Simple wrapping layout for symptom chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
