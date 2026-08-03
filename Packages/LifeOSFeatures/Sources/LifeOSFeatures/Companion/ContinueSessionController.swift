import Foundation
import LifeOSCore

/// Companion work session — restores context without auto-starting a Pomodoro timer.
@MainActor
public final class ContinueSessionController: ObservableObject {
    @Published public private(set) var isPresented = false
    @Published public private(set) var phase: ContinueSessionPhase = .restoring
    @Published public private(set) var context: ContinueSessionContext?
    @Published public private(set) var elapsedSeconds: Int = 0
    @Published public private(set) var hasUserStartedWork = false
    @Published public private(set) var restorationError: String?

    private var elapsedTimer: Timer?

    public init() {}

    public func open(context: ContinueSessionContext) {
        let title = context.workingContext.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.context = context
        hasUserStartedWork = false
        elapsedSeconds = 0
        elapsedTimer?.invalidate()
        restorationError = nil

        if title.isEmpty {
            phase = .failed
            restorationError = "We couldn't restore your previous workspace."
        } else {
            phase = .restoring
        }
        isPresented = true
    }

    public func finishRestoring() {
        guard phase == .restoring else { return }
        phase = .workspace
    }

    public func failRestoration(message: String = "We couldn't restore your previous workspace.") {
        guard phase == .restoring else { return }
        restorationError = message
        phase = .failed
    }

    /// User explicitly chooses to begin — starts an elapsed (count-up) timer only.
    public func beginWork() {
        guard phase == .workspace else { return }
        hasUserStartedWork = true
        phase = .active
        startElapsedTimer()
    }

    public func pauseWork() {
        elapsedTimer?.invalidate()
    }

    public func resumeWork() {
        guard hasUserStartedWork, phase == .active else { return }
        startElapsedTimer()
    }

    public func endSession() {
        elapsedTimer?.invalidate()
        isPresented = false
        phase = .restoring
        context = nil
        elapsedSeconds = 0
        hasUserStartedWork = false
        restorationError = nil
    }

    public var elapsedLabel: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }
}
