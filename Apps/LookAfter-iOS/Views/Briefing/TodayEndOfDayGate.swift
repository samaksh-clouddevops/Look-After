import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// V5: Hide the full end-of-day journal until evening (or explicit expand).
struct TodayEndOfDayGate: View {
    @ObservedObject var modulesVM: LifeModulesViewModel
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var speechManager: SpeechRecognitionManager

    @State private var isExpanded = false

    private var isEvening: Bool {
        Calendar.current.component(.hour, from: Date()) >= 17
    }

    var body: some View {
        if isEvening || isExpanded {
            TodayEndOfDayJournalCard(
                modulesVM: modulesVM,
                tasksVM: tasksVM,
                speechManager: speechManager
            )
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded = true }
            } label: {
                HStack(spacing: DesignSystem.spacingSM) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.accentPrimary)
                    Text("End of day reflection")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.textSecondary)
                    Spacer(minLength: 0)
                    Text("Open")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.accentPrimary)
                }
                .padding(.horizontal, DesignSystem.spacingMD)
                .frame(maxWidth: .infinity, minHeight: DesignSystem.minTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                        .fill(DesignSystem.contentSurfaceSubtle)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open end of day reflection")
            .padding(.top, DesignSystem.spacingMD)
        }
    }
}
