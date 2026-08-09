import SwiftUI
import LookAfterCore
import LookAfterFeatures

struct ContextualReplanSheetsModifier: ViewModifier {
    @Binding var showPostWakeSheet: Bool
    @Binding var showGoingOutSheet: Bool
    @Binding var showContextualReplanPreview: Bool

    let suggestedWakeTime: Date?
    let planningVM: ExecutivePlanningViewModel
    let taskTitles: [String: String]
    let userId: String
    let onPostWakeSubmit: (Date) async -> Void
    let onGoingOutSubmit: (Date, Int) async -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPostWakeSheet) {
                PostWakeReplanSheet(
                    suggestedWakeTime: suggestedWakeTime ?? PostWakeSessionStore.explicitWakeTime()
                ) { wakeTime in
                    await onPostWakeSubmit(wakeTime)
                }
            }
            .sheet(isPresented: $showGoingOutSheet) {
                GoingOutSheet { departure, duration in
                    await onGoingOutSubmit(departure, duration)
                }
            }
            .sheet(isPresented: $showContextualReplanPreview) {
                if let result = planningVM.contextualReplanResult {
                    ContextualReplanPreviewSheet(
                        planningVM: planningVM,
                        result: result,
                        taskTitles: taskTitles,
                        userId: userId,
                        onRegenerate: {
                            await planningVM.regenerateContextualReplan()
                        }
                    )
                }
            }
            .onChange(of: planningVM.contextualReplanResult?.summary) { _, summary in
                showContextualReplanPreview = summary != nil
            }
    }
}
