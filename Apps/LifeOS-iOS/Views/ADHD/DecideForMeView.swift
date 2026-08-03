import SwiftUI
import LifeOSCore
import LifeOSAI
import LifeOSFeatures

/// Zero-Choice Mode: Displays ONLY 1 single task to eliminate choice paralysis for ADHD users.
public struct DecideForMeView: View {

    let task: LifeTask
    let reason: String
    @ObservedObject var adhdVM: ADHDViewModel
    @Environment(\.dismiss) private var dismiss

    public init(task: LifeTask, reason: String = "Selected based on your current energy and available time.", adhdVM: ADHDViewModel) {
        self.task = task
        self.reason = reason
        self.adhdVM = adhdVM
    }

    public var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: DesignSystem.spacingLG) {
                HStack {
                    Spacer()
                    PremiumIconButton("xmark.circle.fill") { dismiss() }
                }
                .screenPadding()

                TagChipView("Zero-choice decision", icon: "sparkles", style: .accent)

                ElevatedSurface(emphasis: .prominent) {
                    PremiumHeroBlock(
                        title: task.title,
                        subtitle: reason,
                        duration: task.steps.first.map { "First step: \($0.title)" }
                    )
                }
                .screenPadding()

                PremiumPrimaryButton("Start this task", icon: "play.fill") {
                    dismiss()
                    adhdVM.startCountdown(for: task) {
                        adhdVM.startFocusSession(task: task)
                    }
                }
                .screenPadding()

                Spacer(minLength: 0)
            }
            .padding(.top, DesignSystem.spacingMD)
        }
    }
}
