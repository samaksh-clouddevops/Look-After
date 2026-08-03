import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Preview sheet for AI-generated day reschedule proposals.
struct ReschedulePreviewSheet: View {
    @ObservedObject var plannerVM: DailyPlannerViewModel
    let proposal: DayRescheduleProposal
    let userId: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                        Text(proposal.summary)
                            .font(.dsBody())
                            .foregroundColor(DesignSystem.textSecondary)
                            .dsPrimaryText(lineLimit: 4)

                        if proposal.movedCount > 0 {
                            Text("\(proposal.movedCount) task\(proposal.movedCount == 1 ? "" : "s") moved")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundColor(DesignSystem.accentPrimary)
                        }

                        ForEach(proposal.changes) { change in
                            changeRow(change)
                        }
                    }
                    .padding(DesignSystem.spacingLG)
                }
            }
            .navigationTitle("Replan Preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject") {
                        plannerVM.rejectRescheduleProposal()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        Task {
                            await plannerVM.applyRescheduleProposal(userId: userId)
                            dismiss()
                        }
                    }
                    .disabled(plannerVM.isScheduling)
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Button("Regenerate") {
                        Task { await plannerVM.regenerateRescheduleProposal(userId: userId) }
                    }
                    .disabled(plannerVM.isScheduling)
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Regenerate") {
                        Task { await plannerVM.regenerateRescheduleProposal(userId: userId) }
                    }
                    .disabled(plannerVM.isScheduling)
                }
                #endif
            }
        }
        .accessibilityIdentifier("screen-reschedule-preview")
    }

    @ViewBuilder
    private func changeRow(_ change: DayScheduleChange) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                Image(systemName: change.isFixed ? "lock.fill" : (change.wasMoved ? "arrow.triangle.2.circlepath" : "checkmark.circle"))
                    .foregroundColor(change.isFixed ? DesignSystem.warning : (change.wasMoved ? DesignSystem.accentPrimary : DesignSystem.success))
                    .layoutPriority(1)

                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    Text(change.taskTitle)
                        .font(.dsBody(weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .dsPrimaryText(lineLimit: 2)

                    HStack(spacing: DesignSystem.spacingSM) {
                        if let previous = change.previousTime, change.wasMoved {
                            Text(previous.formatted(date: .omitted, time: .shortened))
                                .font(.dsCaption())
                                .foregroundColor(DesignSystem.textMuted)
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.dsCaption())
                                .foregroundColor(DesignSystem.textMuted)
                        }
                        Text(change.proposedTime.formatted(date: .omitted, time: .shortened))
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }

                    Text(change.reason)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .dsPrimaryText(lineLimit: 3)
                }
                .layoutPriority(0)
            }
        }
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
    }
}
