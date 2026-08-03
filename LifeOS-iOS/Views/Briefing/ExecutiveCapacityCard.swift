import SwiftUI
import LifeOSCore

/// Renders Brain-inferred Executive Capacity — no percentages, one calm interpretation.
struct ExecutiveCapacityCard: View {
    let capacity: ExecutiveCapacityState
    var compact: Bool = false

    @State private var showWhyDetails = false

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: - Full (Today)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            Text("Executive Capacity")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
                .textCase(.uppercase)
                .tracking(0.6)

            Text(capacity.band.displayLabel)
                .font(.system(size: 32, weight: .bold, design: .default))
                .foregroundColor(bandColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(capacity.band.tagline)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.textSecondary)

            if !capacity.reasoning.reasons.isEmpty {
                reasonsSection
            }

            bestUseSection

            if !capacity.forecast.isEmpty {
                forecastSection
            }

            if capacity.reasoning.detailSummary != nil {
                whyButton
            }
        }
        .padding(DesignSystem.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundElevated)
        )
        .sheet(isPresented: $showWhyDetails) {
            whyDetailSheet
        }
    }

    // MARK: - Compact (Briefing)

    private var compactBody: some View {
        BriefingCardContainer(
            title: "Executive Capacity",
            icon: "brain.head.profile",
            iconGradient: DesignSystem.energyGradient,
            compact: true
        ) {
            Text(capacity.band.displayLabel)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(bandColor)

            Text(capacity.band.tagline)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DesignSystem.textSecondary)

            if !capacity.reasoning.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Because")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                    ForEach(capacity.reasoning.reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(DesignSystem.textMuted)
                            Text(reason)
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                }
                .padding(.top, 4)
            }

            if !capacity.reasoning.recommendedWorkTypes.isEmpty {
                Text("Best: \(capacity.reasoning.recommendedWorkTypes.prefix(2).joined(separator: ", "))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.textMuted)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Sections

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Because")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)

            ForEach(capacity.reasoning.reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(DesignSystem.textMuted)
                    Text(reason)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var bestUseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best use right now")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)

            ForEach(capacity.reasoning.recommendedWorkTypes, id: \.self) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(DesignSystem.accentPrimary)
                    Text(item)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.textPrimary)
                }
            }

            if !capacity.reasoning.avoidWorkTypes.isEmpty {
                ForEach(capacity.reasoning.avoidWorkTypes.prefix(2), id: \.self) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(DesignSystem.textMuted)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Forecast")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
                .padding(.bottom, 10)

            ForEach(Array(capacity.forecast.enumerated()), id: \.element.id) { index, point in
                HStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(index == 0 ? bandColor : DesignSystem.textMuted.opacity(0.5))
                            .frame(width: 8, height: 8)
                        if index < capacity.forecast.count - 1 {
                            Rectangle()
                                .fill(DesignSystem.textMuted.opacity(0.25))
                                .frame(width: 1, height: 28)
                        }
                    }
                    .frame(width: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.timeLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.textSecondary)
                        Text(point.band.shortLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DesignSystem.textPrimary)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var whyButton: some View {
        Button {
            showWhyDetails = true
        } label: {
            Text("Why?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.accentPrimary)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var whyDetailSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                    if let detail = capacity.reasoning.detailSummary {
                        Text(detail)
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.textSecondary)
                    }

                    Text("Confidence: \(Int(capacity.confidence * 100))%")
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textMuted)

                    Text("Recalculated \(capacity.calculatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.textMuted)
                }
                .padding(DesignSystem.spacingLG)
            }
            .background(DesignSystem.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Why this capacity?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showWhyDetails = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var bandColor: Color {
        switch capacity.band {
        case .peakFocus: return DesignSystem.accentPrimary
        case .goodCapacity: return Color(hex: "86EFAC")
        case .moderateCapacity: return Color(hex: "93C5FD")
        case .lowCapacity: return Color(hex: "FDBA74")
        case .recoveryMode: return Color(hex: "C4B5FD")
        }
    }
}
