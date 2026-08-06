import SwiftUI
import LookAfterCore
import LookAfterFeatures

// MARK: - Simulation visual tokens (dry-run sandbox)

private enum SimulationVisuals {
    static let tint = Color(hex: "6366F1") // Indigo
    static let tintSoft = Color(hex: "6366F1").opacity(0.12)
    static let glow = Color(hex: "A78BFA")
    static let headerSize: CGFloat = 27
    static let subHeaderSize: CGFloat = 17
    static let bodySize: CGFloat = 15
    static let captionSize: CGFloat = 13
}

// MARK: - Simulation Timeline View

/// What-If dry-run surface. Pure in-memory `SimulationResult` — Commit writes via intent.
struct SimulationTimelineView: View {
    let result: SimulationResult
    var onDiscard: () -> Void
    var onCommit: (SimulationCommitIntent) -> Void

    @Environment(\.dismiss) private var dismiss

    private var impact: SimulationImpactReport { result.impact }
    private var hypotheticalIDs: Set<String> { Set(result.impact.hypotheticalTaskIDs) }

    private var timelineTasks: [LifeTask] {
        result.simulatedState.activeTasks
            .filter { $0.status.isActive || $0.status == .superseded }
            .sorted { lhs, rhs in
                let l = lhs.scheduledTime ?? .distantFuture
                let r = rhs.scheduledTime ?? .distantFuture
                if l != r { return l < r }
                return lhs.title < rhs.title
            }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                sandboxBackground

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                            impactBanner
                            timelineSection
                        }
                        .padding(.horizontal, DesignSystem.spacingMD)
                        .padding(.top, DesignSystem.spacingMD)
                        .padding(.bottom, 120)
                    }

                    actionFooter
                }
            }
            .navigationTitle("What-If Preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SimulationVisuals.tint.opacity(0.18), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { discard() }
                }
            }
        }
        .accessibilityIdentifier("screen-simulation-timeline")
    }

    // MARK: - Background

    private var sandboxBackground: some View {
        ZStack {
            DesignSystem.backgroundPrimary.ignoresSafeArea()
            SimulationVisuals.tintSoft.ignoresSafeArea()
            GeometryReader { geo in
                Canvas { context, size in
                    let step: CGFloat = 14
                    var path = Path()
                    var x: CGFloat = 0
                    while x < size.width + size.height {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x - size.height, y: size.height))
                        x += step
                    }
                    context.stroke(
                        path,
                        with: .color(SimulationVisuals.tint.opacity(0.08)),
                        lineWidth: 1
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - Impact banner

    private var impactBanner: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(spacing: 8) {
                Image(systemName: severityIcon)
                    .font(.system(size: SimulationVisuals.subHeaderSize, weight: .semibold))
                    .foregroundColor(severityColor)
                Text("Impact")
                    .font(.system(size: SimulationVisuals.subHeaderSize, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                Spacer()
                Text(severityLabel)
                    .font(.system(size: SimulationVisuals.captionSize, weight: .semibold))
                    .foregroundColor(severityColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(severityColor.opacity(0.15)))
            }

            Text(impact.summaryMessage.isEmpty ? defaultSummary : impact.summaryMessage)
                .font(.system(size: SimulationVisuals.bodySize, weight: .medium))
                .foregroundColor(DesignSystem.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: DesignSystem.spacingSM
            ) {
                metricChip("Parked Δ", value: signed(impact.parkedTaskDelta), warn: impact.parkedTaskDelta > 0)
                metricChip("Superseded Δ", value: signed(impact.supersededTasksDelta), warn: impact.supersededTasksDelta > 0)
                metricChip("High-load Δ", value: signed(impact.highLoadStreakDelta), warn: impact.highLoadStreakDelta > 0)
                metricChip("Sabotage", value: "\(impact.sabotageAuctionsTriggered)", warn: impact.sabotageAuctionsTriggered > 0)
            }
        }
        .padding(DesignSystem.spacingLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                        .stroke(severityColor.opacity(0.45), lineWidth: 1.5)
                )
        )
    }

    private var defaultSummary: String {
        impact.absorbsSmoothly
            ? "Schedule absorbs this smoothly"
            : "Review how this hypothetical reshapes the day."
    }

    private func metricChip(_ title: String, value: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: SimulationVisuals.captionSize, weight: .semibold))
                .foregroundColor(DesignSystem.textMuted)
            Text(value)
                .font(.system(size: SimulationVisuals.subHeaderSize, weight: .bold))
                .foregroundColor(warn ? DesignSystem.warning : DesignSystem.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                .fill(DesignSystem.backgroundElevated.opacity(0.65))
        )
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            Text("Simulated Day")
                .font(.system(size: SimulationVisuals.headerSize, weight: .bold))
                .foregroundColor(DesignSystem.textPrimary)

            if timelineTasks.isEmpty {
                Text("No scheduled blocks after simulation.")
                    .font(.system(size: SimulationVisuals.bodySize))
                    .foregroundColor(DesignSystem.textSecondary)
                    .padding(.vertical, DesignSystem.spacingMD)
            } else {
                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(timelineTasks) { task in
                        simulationRow(task)
                    }
                }
            }
        }
    }

    private func simulationRow(_ task: LifeTask) -> some View {
        let isHypothetical = hypotheticalIDs.contains(task.id)
        let timeLabel: String = {
            if let start = task.scheduledTime {
                let end = task.scheduledEndTime
                    ?? start.addingTimeInterval(TimeInterval(max(task.estimatedMinutes, 1) * 60))
                let f = DateFormatter()
                f.timeStyle = .short
                return "\(f.string(from: start)) – \(f.string(from: end))"
            }
            return task.status == .superseded ? "Superseded" : "Unscheduled"
        }()

        return HStack(alignment: .top, spacing: DesignSystem.spacingMD) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isHypothetical ? SimulationVisuals.glow : SimulationVisuals.tint.opacity(0.55))
                    .frame(width: isHypothetical ? 12 : 8, height: isHypothetical ? 12 : 8)
                    .shadow(color: isHypothetical ? SimulationVisuals.glow.opacity(0.8) : .clear, radius: 6)
                Rectangle()
                    .fill(SimulationVisuals.tint.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.system(size: SimulationVisuals.bodySize, weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .lineLimit(2)
                    if isHypothetical {
                        Text("WHAT-IF")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(SimulationVisuals.tint))
                    }
                    Spacer(minLength: 0)
                }
                Text(timeLabel)
                    .font(.system(size: SimulationVisuals.captionSize, weight: .medium))
                    .foregroundColor(DesignSystem.textSecondary)
                if task.estimatedMinutes > 0 {
                    Text("\(task.estimatedMinutes) min · \(task.priority.label)")
                        .font(.system(size: SimulationVisuals.captionSize))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            .padding(DesignSystem.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary)
                    .shadow(
                        color: isHypothetical ? SimulationVisuals.glow.opacity(0.45) : .clear,
                        radius: isHypothetical ? 10 : 0,
                        y: 0
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .stroke(
                        isHypothetical ? SimulationVisuals.glow : Color.clear,
                        lineWidth: isHypothetical ? 2 : 0
                    )
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Footer

    private var actionFooter: some View {
        HStack(spacing: DesignSystem.spacingMD) {
            Button(action: discard) {
                Text("Discard")
                    .font(.system(size: SimulationVisuals.subHeaderSize, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusButton, style: .continuous)
                            .stroke(DesignSystem.border, lineWidth: 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusButton, style: .continuous)
                                    .fill(DesignSystem.backgroundSecondary)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard simulation")

            Button(action: commit) {
                Text("Commit Schedule")
                    .font(.system(size: SimulationVisuals.subHeaderSize, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusButton, style: .continuous)
                            .fill(SimulationVisuals.tint)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Commit simulated schedule")
        }
        .padding(.horizontal, DesignSystem.spacingMD)
        .padding(.top, DesignSystem.spacingMD)
        .padding(.bottom, DesignSystem.spacingLG)
        .background(
            DesignSystem.backgroundPrimary
                .opacity(0.96)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions / severity

    private func discard() {
        onDiscard()
        dismiss()
    }

    private func commit() {
        let intent = LifeEngine.shared.commitSimulationIntent(from: result)
        onCommit(intent)
        dismiss()
    }

    private var severityColor: Color {
        switch impact.severity {
        case .success: return DesignSystem.success
        case .neutral: return SimulationVisuals.tint
        case .warning: return DesignSystem.warning
        case .critical: return DesignSystem.error
        }
    }

    private var severityIcon: String {
        switch impact.severity {
        case .success: return "checkmark.seal.fill"
        case .neutral: return "sparkles"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "flame.fill"
        }
    }

    private var severityLabel: String {
        switch impact.severity {
        case .success: return "Smooth"
        case .neutral: return "Neutral"
        case .warning: return "Caution"
        case .critical: return "High impact"
        }
    }

    private func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        return "\(value)"
    }
}
