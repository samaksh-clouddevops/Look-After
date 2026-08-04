import SwiftUI
import Combine

@MainActor
final class AppFeatureTourCoordinator: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var stepIndex = 0
    @Published var requestedTab: LookAfterTab?
    @Published var anchorFrames: [AppFeatureTourAnchorID: CGRect] = [:]

    let steps = AppFeatureTourStep.all

    var currentStep: AppFeatureTourStep {
        steps[min(stepIndex, steps.count - 1)]
    }

    var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    var progressLabel: String {
        "Step \(stepIndex + 1) of \(steps.count)"
    }

    func start(force: Bool = false) {
        guard !isActive else { return }
        guard force || AppFeatureTourStore.shouldPresent else { return }
        stepIndex = 0
        requestedTab = currentStep.tab
        isActive = true
    }

    func advance() {
        guard isActive else { return }
        if isLastStep {
            complete()
            return
        }
        stepIndex += 1
        requestedTab = currentStep.tab
    }

    func goBack() {
        guard isActive, stepIndex > 0 else { return }
        stepIndex -= 1
        requestedTab = currentStep.tab
    }

    func skip() {
        complete()
    }

    func complete() {
        AppFeatureTourStore.markCompleted()
        isActive = false
        stepIndex = 0
        requestedTab = nil
    }

    func highlightFrame(padding: CGFloat = 10) -> CGRect? {
        guard let anchor = currentStep.anchor,
              let frame = anchorFrames[anchor],
              frame.width > 0,
              frame.height > 0 else { return nil }
        return frame.insetBy(dx: -padding, dy: -padding)
    }
}
