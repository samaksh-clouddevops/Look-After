import SwiftUI
import Combine
import LookAfterCore
import UIKit

/// Tour engine façade: step flow, anchor registry, adaptive layout, persistence.
@MainActor
final class AppFeatureTourCoordinator: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var stepIndex = 0
    @Published var requestedTab: LookAfterTab?
    @Published private(set) var layoutProposal: TourLayoutProposal?
    @Published private(set) var isAwaitingScroll = false

    /// Rich anchor registry (frame + corner radius + visibility).
    @Published var anchors: [AppFeatureTourAnchorID: TourAnchorGeometry] = [:]

    /// Compatibility bridge used by RootCanvas preference collector.
    var anchorFrames: [AppFeatureTourAnchorID: CGRect] {
        get {
            anchors.mapValues(\.frame)
        }
        set {
            for (id, frame) in newValue {
                var geometry = anchors[id] ?? .empty
                geometry.frame = frame
                geometry.isVisible = frame.width > 0.5 && frame.height > 0.5
                anchors[id] = geometry
            }
            scheduleLayoutRecompute()
        }
    }

    let steps = AppFeatureTourStep.all

    /// Live layout chrome — updated by the overlay from GeometryReader / keyboard.
    var screenBounds: CGRect = UIScreen.main.bounds
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    var keyboardFrame: CGRect = .null
    var tabBarFrame: CGRect = .null
    var measuredCardSize: CGSize = CGSize(width: 320, height: 220)

    private var layoutWorkItem: DispatchWorkItem?
    private var scrollWaitTask: Task<Void, Never>?
    private var lastScrollPostAt: Date = .distantPast
    nonisolated(unsafe) private var keyboardObservers: [NSObjectProtocol] = []

    var currentStep: AppFeatureTourStep {
        steps[min(max(0, stepIndex), steps.count - 1)]
    }

    var isLastStep: Bool { stepIndex >= steps.count - 1 }

    var progressLabel: String {
        "Step \(stepIndex + 1) of \(steps.count)"
    }

    var currentHighlightCornerRadius: CGFloat {
        guard let id = currentStep.anchor else { return 16 }
        return anchors[id]?.cornerRadius ?? 16
    }

    init() {
        observeKeyboard()
    }

    deinit {
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Lifecycle

    func start(force: Bool = false) {
        guard !isActive else { return }

        if !force, let restored = AppFeatureTourStore.restoreProgress() {
            stepIndex = min(restored.stepIndex, max(steps.count - 1, 0))
            requestedTab = currentStep.tab
            isActive = true
            persistProgress()
            requestScrollIfNeeded()
            scheduleLayoutRecompute(delay: 0.2)
            return
        }

        guard force || AppFeatureTourStore.shouldPresent else { return }
        stepIndex = 0
        requestedTab = currentStep.tab
        isActive = true
        persistProgress()
        requestScrollIfNeeded()
        scheduleLayoutRecompute(delay: 0.2)
    }

    func advance() {
        guard isActive else { return }
        if isLastStep {
            complete()
            return
        }
        stepIndex += 1
        requestedTab = currentStep.tab
        layoutProposal = nil
        persistProgress()
        requestScrollIfNeeded()
        scheduleLayoutRecompute(delay: 0.2)
    }

    func goBack() {
        guard isActive, stepIndex > 0 else { return }
        stepIndex -= 1
        requestedTab = currentStep.tab
        layoutProposal = nil
        persistProgress()
        requestScrollIfNeeded()
        scheduleLayoutRecompute(delay: 0.2)
    }

    func skip() { complete() }

    func complete() {
        scrollWaitTask?.cancel()
        AppFeatureTourStore.markCompleted()
        isActive = false
        stepIndex = 0
        requestedTab = nil
        layoutProposal = nil
        isAwaitingScroll = false
    }

    // MARK: - Anchor API

    func updateAnchor(_ id: AppFeatureTourAnchorID, frame: CGRect, cornerRadius: CGFloat = 16) {
        anchors[id] = TourAnchorGeometry(
            frame: frame,
            cornerRadius: cornerRadius,
            isVisible: frame.width > 0.5 && frame.height > 0.5
        )
        scheduleLayoutRecompute()
    }

    /// Full preference snapshot — replaces registry so stale off-screen anchors drop out.
    func replaceAnchors(_ payloads: [AppFeatureTourAnchorID: AppFeatureTourAnchorPayload]) {
        let prior = anchors
        var next: [AppFeatureTourAnchorID: TourAnchorGeometry] = [:]
        for (id, payload) in payloads {
            next[id] = TourAnchorGeometry(
                frame: payload.frame,
                cornerRadius: payload.cornerRadius,
                isVisible: payload.frame.width > 0.5 && payload.frame.height > 0.5
            )
        }
        anchors = next
        guard isActive else { return }
        if anchorMeaningfullyChanged(from: prior, to: next, focus: currentStep.anchor) {
            scheduleLayoutRecompute(delay: 0.12)
        }
    }

    func updateLayoutChrome(
        screenBounds: CGRect,
        safeArea: EdgeInsets,
        tabBarFrame: CGRect = .null,
        cardSize: CGSize? = nil
    ) {
        let boundsChanged = !screenBounds.equal(to: self.screenBounds, epsilon: 1)
        let safeChanged = safeArea != self.safeAreaInsets
        let cardChanged: Bool = {
            guard let cardSize, cardSize.width > 1, cardSize.height > 1 else { return false }
            return abs(cardSize.width - measuredCardSize.width) > 2
                || abs(cardSize.height - measuredCardSize.height) > 2
        }()

        guard boundsChanged || safeChanged || cardChanged else { return }

        self.screenBounds = screenBounds
        self.safeAreaInsets = safeArea
        if tabBarFrame.isValidObstacle {
            self.tabBarFrame = tabBarFrame
        }
        if let cardSize, cardChanged {
            measuredCardSize = cardSize
        }
        scheduleLayoutRecompute(delay: 0.12)
    }

    // MARK: - Highlight helpers

    func rawHighlightFrame() -> CGRect? {
        guard let id = currentStep.anchor,
              let geometry = anchors[id],
              geometry.isValid else { return nil }
        return geometry.frame
    }

    func highlightFrame(padding: CGFloat = 10) -> CGRect? {
        guard let frame = rawHighlightFrame() else { return nil }
        return frame.insetBy(dx: -padding, dy: -padding)
    }

    // MARK: - Layout

    func recomputeLayout() {
        guard isActive else {
            layoutProposal = nil
            return
        }

        let metrics = makeMetrics()
        let proposal = TourPlacementEngine.propose(
            highlight: rawHighlightFrame(),
            metrics: metrics
        )

        if proposal.needsScroll,
           let anchor = currentStep.anchor,
           anchor != .briefingHero {
            postScrollRequest(anchor: anchor, offset: proposal.suggestedScrollOffset)
        }

        if layoutProposal != proposal {
            layoutProposal = proposal
        }
    }

    private func makeMetrics() -> TourLayoutMetrics {
        var preferred = currentStep.preferredSides
        // Always allow engine to fall through the full side set.
        for side in TourCardSide.allCases where !preferred.contains(side) {
            preferred.append(side)
        }

        let assistantFrame = anchors[.todayAssistant]?.frame ?? .null
        let bottomSheet: CGRect = {
            guard currentStep.anchor != .todayAssistant,
                  anchors[.todayAssistant]?.isValid == true,
                  assistantFrame.isValidObstacle else { return .null }
            return assistantFrame
        }()

        let layoutWidth = min(
            DesignSystem.readableMaxWidth,
            max(240, screenBounds.width - DesignSystem.spacingMD * 2)
        )
        let cardSize = CGSize(
            width: layoutWidth,
            height: max(measuredCardSize.height, 160)
        )

        return TourLayoutMetrics(
            screenBounds: screenBounds,
            safeAreaInsets: TourEdgeInsets(
                top: safeAreaInsets.top,
                left: safeAreaInsets.leading,
                bottom: safeAreaInsets.bottom,
                right: safeAreaInsets.trailing
            ),
            keyboardFrame: keyboardFrame,
            tabBarFrame: tabBarFrame,
            bottomSheetFrame: bottomSheet,
            cardSize: cardSize,
            cardMargin: DesignSystem.spacingMD,
            highlightPadding: 10,
            minimumGap: DesignSystem.spacingSM,
            arrowLength: 10,
            topObstacleInset: 12,
            preferredSides: preferred
        )
    }

    private func anchorMeaningfullyChanged(
        from prior: [AppFeatureTourAnchorID: TourAnchorGeometry],
        to next: [AppFeatureTourAnchorID: TourAnchorGeometry],
        focus: AppFeatureTourAnchorID?
    ) -> Bool {
        guard let focus else { return false }
        let oldFrame = prior[focus]?.frame ?? .null
        let newFrame = next[focus]?.frame ?? .null
        return !oldFrame.equal(to: newFrame, epsilon: 2)
    }

    func scheduleLayoutRecomputeIfActive() {
        guard isActive else { return }
        scheduleLayoutRecompute(delay: 0.12)
    }

    private func scheduleLayoutRecompute(delay: TimeInterval = 0.12) {
        layoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.recomputeLayout()
        }
        layoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func requestScrollIfNeeded() {
        guard let anchor = currentStep.anchor else { return }
        isAwaitingScroll = true
        postScrollRequest(anchor: anchor, offset: 0)
        scrollWaitTask?.cancel()
        scrollWaitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            self.isAwaitingScroll = false
            self.recomputeLayout()
        }
    }

    private func postScrollRequest(anchor: AppFeatureTourAnchorID, offset: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollPostAt) > 0.45 else { return }
        lastScrollPostAt = now
        NotificationCenter.default.post(
            name: .tourScrollToAnchor,
            object: nil,
            userInfo: [
                TourScrollUserInfoKey.anchorID: anchor.rawValue,
                TourScrollUserInfoKey.offset: offset,
                TourScrollUserInfoKey.scrollAnchor: anchor.tourScrollAnchor
            ]
        )
    }

    private func persistProgress() {
        AppFeatureTourStore.saveProgress(stepIndex: stepIndex, isActive: isActive)
    }

    // MARK: - Keyboard

    private func observeKeyboard() {
        let center = NotificationCenter.default
        keyboardObservers.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
            Task { @MainActor [weak self] in
                guard let self else { return }
                let intersects = frame.intersects(self.screenBounds) && frame.minY < self.screenBounds.maxY - 1
                self.keyboardFrame = intersects ? frame : .null
                self.scheduleLayoutRecompute(delay: 0.02)
            }
        })
        keyboardObservers.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.keyboardFrame = .null
                self?.scheduleLayoutRecompute(delay: 0.02)
            }
        })
    }
}

private extension CGRect {
    func equal(to other: CGRect, epsilon: CGFloat) -> Bool {
        abs(minX - other.minX) <= epsilon
            && abs(minY - other.minY) <= epsilon
            && abs(width - other.width) <= epsilon
            && abs(height - other.height) <= epsilon
    }
}
