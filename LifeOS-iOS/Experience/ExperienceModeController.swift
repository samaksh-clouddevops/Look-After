import SwiftUI
import LifeOSCore

/// Observable wrapper for instant experience switching without app restart.
@MainActor
final class ExperienceModeController: ObservableObject {
    @Published private(set) var mode: ExperienceMode

    init() {
        mode = ExperienceMode.current
    }

    func setMode(_ newMode: ExperienceMode) {
        guard mode != newMode else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            mode = newMode
        }
        ExperienceMode.save(newMode)
    }

    var isAIExecutive: Bool { mode == .aiExecutive }
}
