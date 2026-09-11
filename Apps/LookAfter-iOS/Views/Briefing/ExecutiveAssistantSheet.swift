import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Planning conversation presented as a sheet from Today's Plan toolbar control.
/// Never shown as a persistent floating dock above the tab bar.
struct ExecutiveAssistantSheet: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    @ObservedObject var speechManager: SpeechRecognitionManager
    @ObservedObject var speechSynthesizer: PlanningSpeechSynthesizer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var onSubmit: (_ text: String, _ startedWithVoice: Bool) -> Void
    var onNegotiationSelect: (String) -> Void
    var onApprovePendingPlan: () -> Void = {}
    var onRejectPendingPlan: () -> Void = {}
    var onRedesignWithAI: (String) -> Void = { _ in }
    var onPostWake: () -> Void = {}
    var onGoingOut: () -> Void = {}

    var body: some View {
        NavigationStack {
            ExecutivePlanningConversationView(
                planningVM: planningVM,
                speechManager: speechManager,
                speechSynthesizer: speechSynthesizer,
                isExpanded: true,
                maxPanelHeight: nil,
                onSubmit: onSubmit,
                onNegotiationSelect: onNegotiationSelect,
                onApprovePendingPlan: onApprovePendingPlan,
                onRejectPendingPlan: onRejectPendingPlan,
                onRedesignWithAI: onRedesignWithAI,
                onExpand: {},
                onStartVoice: {
                    planningVM.setInputMode(.voice)
                },
                onStartTyping: {},
                onPostWake: onPostWake,
                onGoingOut: onGoingOut
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(sheetBackground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        speechManager.stopListening()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.accentPrimary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done")
                }
            }
        }
        .onChange(of: planningVM.isProcessing) { _, processing in
            if processing, planningVM.inputMode == .voice {
                VoiceSessionKeepAlive.begin("planning-voice-processing")
            } else if !processing {
                VoiceSessionKeepAlive.end("planning-voice-processing")
            }
        }
        .accessibilityIdentifier("screen-assistant-sheet")
    }

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency {
            DesignSystem.backgroundSecondary
        } else {
            DesignSystem.backgroundPrimary
        }
    }
}
