import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Morning supervisor card — faults, pulls, questions (max 2), approve chips.
struct DayAuditCheckCard: View {
    @ObservedObject var briefingVM: DailyBriefingViewModel
    @ObservedObject var tasksVM: TasksViewModel
    var userId: String = ""
    @State private var showParkedReview = false

    var body: some View {
        Group {
            if let audit = briefingVM.dayAudit, audit.hasMaterialFindings || audit.hasBlockingQuestions {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                    Text("Today’s check")
                        .textStyleSectionLabel(color: DesignSystem.textSecondary)
                        .textCase(.uppercase)
                        .accessibilityAddTraits(.isHeader)

                    Text(audit.capacitySummary.line)
                        .textStyleBody(color: DesignSystem.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !audit.faults.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                            Text("Needs attention")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundStyle(DesignSystem.textSecondary)
                            ForEach(audit.faults.prefix(3)) { fault in
                                Text("• \(fault.message)")
                                    .textStyleCaption()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !audit.proposedFixes.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                            Text("Suggested fixes")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundStyle(DesignSystem.textSecondary)
                            ForEach(audit.proposedFixes.prefix(4)) { fix in
                                Button {
                                    briefingVM.toggleDayAuditFix(fix.id)
                                } label: {
                                    HStack {
                                        Image(systemName: briefingVM.acceptedDayAuditFixIDs.contains(fix.id)
                                              ? "checkmark.circle.fill"
                                              : "circle")
                                            .foregroundStyle(
                                                briefingVM.acceptedDayAuditFixIDs.contains(fix.id)
                                                ? DesignSystem.accentPrimary
                                                : DesignSystem.textMuted
                                            )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(fix.title)
                                                .font(.dsCaption(weight: .semibold))
                                                .foregroundStyle(DesignSystem.textPrimary)
                                            Text(fix.detail)
                                                .textStyleCaption()
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !audit.possiblePulls.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                            Text("Pull if it fits")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundStyle(DesignSystem.textSecondary)
                            ForEach(audit.possiblePulls) { pull in
                                Button {
                                    briefingVM.toggleDayAuditPull(pull.id)
                                } label: {
                                    HStack {
                                        Image(systemName: briefingVM.selectedDayAuditPullIDs.contains(pull.id)
                                              ? "checkmark.circle.fill"
                                              : "circle")
                                            .foregroundStyle(
                                                briefingVM.selectedDayAuditPullIDs.contains(pull.id)
                                                ? DesignSystem.accentPrimary
                                                : DesignSystem.textMuted
                                            )
                                        Text("\(pull.title) · \(pull.estimatedMinutes)m · \(pull.origin.rawValue)")
                                            .textStyleCaption()
                                            .foregroundStyle(DesignSystem.textPrimary)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !ParkedTaskQueueStore.shared.candidatesForReintegration(limit: 1).isEmpty {
                        Button("Review parked & fluid") {
                            showParkedReview = true
                        }
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.accentPrimary)
                    }

                    if !audit.notPossible.isEmpty {
                        Text("Won’t fit today: " + audit.notPossible.prefix(2).map(\.title).joined(separator: ", "))
                            .textStyleCaption()
                            .foregroundStyle(DesignSystem.textMuted)
                    }

                    if audit.hasBlockingQuestions, !briefingVM.skippedDayAuditQuestions {
                        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                            ForEach(audit.clarifyingQuestions) { question in
                                Text(question.prompt)
                                    .font(.dsCaption(weight: .semibold))
                                    .foregroundStyle(DesignSystem.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                FlowQuestionChips(
                                    options: question.options,
                                    selected: briefingVM.dayAuditQuestionAnswers[question.id]
                                ) { option in
                                    briefingVM.answerDayAuditQuestion(id: question.id, option: option)
                                }
                            }
                            Button("Skip questions") {
                                briefingVM.skipDayAuditQuestions()
                            }
                            .font(.dsCaption(weight: .medium))
                            .foregroundStyle(DesignSystem.textMuted)
                        }
                    }
                }
                .padding(DesignSystem.cardPaddingMin)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .fill(DesignSystem.contentSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .stroke(DesignSystem.border, lineWidth: 1)
                )
                .accessibilityIdentifier("day-audit-check-card")
                .sheet(isPresented: $showParkedReview) {
                    ParkedFluidReviewView(
                        onPullSelected: { entries in
                            _ = ParkedTaskRecoveryService.shared.placeSelected(
                                entries,
                                gapStart: Date(),
                                day: Date(),
                                userId: userId,
                                tasksVM: tasksVM
                            )
                            Task {
                                await briefingVM.refreshDayAudit(tasksVM: tasksVM)
                            }
                        },
                        onDismiss: { showParkedReview = false }
                    )
                }
            }
        }
    }
}

private struct FlowQuestionChips: View {
    let options: [String]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(option)
                        .font(.dsCaption(weight: .medium))
                        .foregroundStyle(
                            selected == option ? DesignSystem.accentOnPrimary : DesignSystem.textPrimary
                        )
                        .padding(.horizontal, DesignSystem.spacingSM)
                        .padding(.vertical, DesignSystem.spacingXS)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selected == option
                            ? DesignSystem.accentPrimary
                            : DesignSystem.textMuted.opacity(0.12)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
