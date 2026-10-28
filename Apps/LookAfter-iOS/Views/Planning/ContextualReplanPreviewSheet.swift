import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Preview sheet for contextual day replans (post-wake, going out).
struct ContextualReplanPreviewSheet: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    let result: DayReplanResult
    let taskTitles: [String: String]
    let userId: String
    let onRegenerate: () async -> Void

    @EnvironmentObject private var shell: AppShellState
    @Environment(\.dismiss) private var dismiss
    @State private var applyError: String?

    private var isBusy: Bool { planningVM.isReplanning || planningVM.isApplyingPlan }

    private var activeResult: DayReplanResult {
        guard let variants = result.planVariants, !variants.isEmpty,
              let selected = planningVM.selectedVariantID,
              let variant = variants.first(where: { $0.id == selected }) else {
            return result
        }
        var merged = result
        merged.summary = variant.summary
        merged.scheduleChanges = variant.scheduleChanges
        merged.timelineDeltas = variant.timelineDeltas
        return merged
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                        if let variants = result.planVariants, variants.count > 1 {
                            variantPicker(variants)
                        }

                        Text(activeResult.summary)
                            .font(.dsBody())
                            .foregroundColor(DesignSystem.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !deferredChanges.isEmpty {
                            sectionHeader("Deferred")
                            ForEach(deferredChanges, id: \.taskID) { change in
                                changeRow(change, icon: "moon.zzz.fill", tint: DesignSystem.textMuted)
                            }
                        }

                        if !rescheduledChanges.isEmpty {
                            sectionHeader("Rescheduled")
                            ForEach(rescheduledChanges, id: \.taskID) { change in
                                changeRow(change, icon: "arrow.triangle.2.circlepath", tint: DesignSystem.accentPrimary)
                            }
                        }

                        Button {
                            Task { await onRegenerate() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Regenerate")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    }
                    .padding(DesignSystem.spacingLG)
                }
            }
            .navigationTitle(planningVM.contextualReplanTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject") {
                        planningVM.rejectContextualReplan()
                        dismiss()
                    }
                    .disabled(isBusy)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(planningVM.isApplyingPlan ? "Saving…" : "Apply") {
                        Task {
                            let saved = await planningVM.applyContextualReplanResult(
                                tasksVM: shell.tasksVM,
                                modulesVM: shell.modulesVM,
                                userId: userId,
                                refreshContext: {
                                    await shell.syncScheduleAfterRescheduleApply(userId: userId)
                                    await MainActor.run {
                                        planningVM.refreshTimeline(from: shell.timelineService.snapshot.today)
                                    }
                                }
                            )
                            if saved {
                                dismiss()
                            } else {
                                applyError = planningVM.errorMessage ?? "Couldn't save the plan. Please try again."
                            }
                        }
                    }
                    .disabled(isBusy)
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .alert("Couldn't apply the plan", isPresented: Binding(
            get: { applyError != nil }, set: { if !$0 { applyError = nil } }
        )) {
            Button("OK", role: .cancel) { applyError = nil }
        } message: {
            Text(applyError ?? "Please try again.")
        }
        .accessibilityIdentifier("screen-contextual-replan-preview")
        .onAppear {
            if planningVM.selectedVariantID == nil {
                planningVM.selectContextualVariant(
                    result.planVariants?.first(where: \.recommended)
                        ?? result.planVariants?.first
                        ?? PlanVariant(
                            label: "Default",
                            summary: result.summary,
                            scheduleChanges: result.scheduleChanges,
                            timelineDeltas: result.timelineDeltas,
                            recommended: true
                        )
                )
            }
        }
    }

    @ViewBuilder
    private func variantPicker(_ variants: [PlanVariant]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            sectionHeader("Choose a plan")
            ForEach(variants) { variant in
                Button {
                    planningVM.selectContextualVariant(variant)
                } label: {
                    HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                        Image(systemName: planningVM.selectedVariantID == variant.id ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(planningVM.selectedVariantID == variant.id ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                            HStack {
                                Text(variant.label)
                                    .font(.dsBody(weight: .semibold))
                                    .foregroundColor(DesignSystem.textPrimary)
                                if variant.recommended {
                                    Text("Recommended")
                                        .font(.dsCaption(weight: .semibold))
                                        .foregroundColor(DesignSystem.accentPrimary)
                                }
                            }
                            Text(variant.summary)
                                .font(.dsCaption())
                                .foregroundColor(DesignSystem.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    private var deferredChanges: [DayReplanScheduleChange] {
        activeResult.effectiveChanges(selectedVariantID: planningVM.selectedVariantID).filter(\.deferToTomorrow)
    }

    private var rescheduledChanges: [DayReplanScheduleChange] {
        activeResult.effectiveChanges(selectedVariantID: planningVM.selectedVariantID).filter { !$0.deferToTomorrow && $0.startHour != nil }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.dsCaption(weight: .semibold))
            .foregroundColor(DesignSystem.textMuted)
            .tracking(0.6)
    }

    @ViewBuilder
    private func changeRow(_ change: DayReplanScheduleChange, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                    Text(taskTitles[change.taskID] ?? "Task")
                        .font(.dsBody(weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if change.deferToTomorrow {
                        Text("Moved to tomorrow")
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)
                    } else if let hour = change.startHour, let minute = change.startMinute {
                        Text(formattedTime(hour: hour, minute: minute))
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }

                    if !change.reason.isEmpty {
                        Text(change.reason)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
