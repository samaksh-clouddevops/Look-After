import Foundation
import SwiftUI
import LookAfterCore

// MARK: - Anchors

enum AppFeatureTourAnchorID: String, Hashable, CaseIterable, Sendable {
    case tabBriefing
    case tabToday
    case tabReview
    case tabCapture
    case tabBrain
    case tabYou
    case briefingHero
    case briefingHealthStrip
    case briefingScrollTop
    case todayTimeline
    case todayAllTasks
    case todayAssistant
    case reviewHero
    case brainVoiceOrb
    case youProfile
}

/// Runtime geometry for a registered tour target.
struct TourAnchorGeometry: Equatable, Sendable {
    var frame: CGRect
    var cornerRadius: CGFloat
    var isVisible: Bool

    static let empty = TourAnchorGeometry(frame: .zero, cornerRadius: 16, isVisible: false)

    var isValid: Bool {
        isVisible && frame.width > 0.5 && frame.height > 0.5
    }
}

// MARK: - Steps

struct AppFeatureTourStep: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let icon: String
    let tab: LookAfterTab?
    let anchor: AppFeatureTourAnchorID?
    /// Soft preference only — engine may override for a collision-free fit.
    let preferredSides: [TourCardSide]
    let allowsTargetInteraction: Bool

    static let all: [AppFeatureTourStep] = [
        AppFeatureTourStep(
            id: "welcome",
            title: "Welcome to Look After",
            message: "A quick tour of the app — six tabs along the bottom: Briefing, Today, Review, Capture, Brain, and You.",
            icon: "sparkles",
            tab: .briefing,
            anchor: nil,
            preferredSides: [.center],
            allowsTargetInteraction: false
        ),
        AppFeatureTourStep(
            id: "briefing",
            title: "Briefing",
            message: "Start each day here. Your AI day summary lives up top — scroll for sleep, energy, and recovery tiles.",
            icon: "doc.text.fill",
            tab: .briefing,
            anchor: .briefingHero,
            preferredSides: [.below, .floating, .center],
            allowsTargetInteraction: false
        ),
        AppFeatureTourStep(
            id: "briefing-health",
            title: "How you're doing",
            message: "Sleep, energy, recovery, and your best focus window — updated through the day, even before HealthKit syncs overnight.",
            icon: "sun.max.fill",
            tab: .briefing,
            anchor: .briefingHealthStrip,
            preferredSides: [.below, .above, .floating],
            allowsTargetInteraction: false
        ),
        AppFeatureTourStep(
            id: "today",
            title: "Today",
            message: "Your live timeline — start focus, reschedule, and see what's now. Tap All tasks to view and edit everything in one place.",
            icon: "calendar",
            tab: .today,
            anchor: .todayTimeline,
            preferredSides: [.below, .above, .floating],
            allowsTargetInteraction: false
        ),
        AppFeatureTourStep(
            id: "assistant",
            title: "Plan With Me",
            message: "Tap Plan in the Today header to replan your day. Talk or type — it reshapes your schedule with you.",
            icon: "sparkles",
            tab: .today,
            anchor: .todayAssistant,
            preferredSides: [.below, .floating, .above],
            allowsTargetInteraction: true
        ),
        AppFeatureTourStep(
            id: "review",
            title: "Weekly Review",
            message: "Open Review from You — weekly debrief without digging through logs.",
            icon: "chart.bar.fill",
            tab: .you,
            anchor: .reviewHero,
            preferredSides: [.below, .floating, .center],
            allowsTargetInteraction: true
        ),
        AppFeatureTourStep(
            id: "capture",
            title: "Capture",
            message: "The Capture tab in the bottom bar — dump a thought, task, or note by voice or text, no sorting required.",
            icon: "plus.circle",
            tab: nil,
            anchor: .tabCapture,
            preferredSides: [.above, .floating],
            allowsTargetInteraction: true
        ),
        AppFeatureTourStep(
            id: "brain",
            title: "Executive Brain",
            message: "Talk to your AI companion. Tap the orb to speak, get coaching, or decide your next move.",
            icon: "brain.head.profile",
            tab: .brain,
            anchor: .brainVoiceOrb,
            preferredSides: [.below, .above, .floating],
            allowsTargetInteraction: true
        ),
        AppFeatureTourStep(
            id: "you",
            title: "You",
            message: "Profile, life areas, inbox, and settings. Life State bars mirror the same signals as Briefing.",
            icon: "person.fill",
            tab: .you,
            anchor: .youProfile,
            preferredSides: [.below, .above, .floating],
            allowsTargetInteraction: false
        ),
        AppFeatureTourStep(
            id: "focus",
            title: "Focus & ADHD tools",
            message: "Start a task for focus mode. Use Decide for Me, body doubling, or a physiological reset from Brain.",
            icon: "timer",
            tab: .briefing,
            anchor: nil,
            preferredSides: [.center],
            allowsTargetInteraction: false
        ),
        AppFeatureTourStep(
            id: "done",
            title: "You're all set",
            message: "Explore at your own pace. Replay anytime from Settings → Help.",
            icon: "checkmark.circle.fill",
            tab: .briefing,
            anchor: nil,
            preferredSides: [.center],
            allowsTargetInteraction: false
        ),
    ]
}

// MARK: - Persistence + restoration

enum AppFeatureTourStore {
    private static let completedKey = "lookafter.hasCompletedFeatureTour"
    private static let stepKey = "lookafter.featureTour.stepIndex"
    private static let activeKey = "lookafter.featureTour.wasActive"
    /// Tracks how many consecutive launches restored the tour still stuck on the same step,
    /// so a step that never renders/advances properly (e.g. bad anchor geometry) can't force
    /// the user to relaunch forever — see AppFeatureTourOverlay's escape-hatch tap-to-advance.
    private static let stuckStepKey = "lookafter.featureTour.stuckStepIndex"
    private static let stuckCountKey = "lookafter.featureTour.stuckStepCount"
    /// After this many launches restoring the exact same unfinished step, auto-skip the tour.
    private static let maxStuckRestores = 2

    static var shouldPresent: Bool {
        !UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: completedKey)
        defaults.set(false, forKey: activeKey)
        defaults.set(0, forKey: stepKey)
        defaults.removeObject(forKey: stuckStepKey)
        defaults.removeObject(forKey: stuckCountKey)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: completedKey)
        defaults.removeObject(forKey: stepKey)
        defaults.removeObject(forKey: activeKey)
        defaults.removeObject(forKey: stuckStepKey)
        defaults.removeObject(forKey: stuckCountKey)
    }

    static func saveProgress(stepIndex: Int, isActive: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(stepIndex, forKey: stepKey)
        defaults.set(isActive, forKey: activeKey)
        // Any real progress (step changed) clears the stuck counter.
        if defaults.integer(forKey: stuckStepKey) != stepIndex {
            defaults.removeObject(forKey: stuckStepKey)
            defaults.removeObject(forKey: stuckCountKey)
        }
    }

    /// Returns the step to restore, or `nil` if there's nothing to restore or the tour has
    /// been stuck on the same step across too many launches (auto-skips instead).
    static func restoreProgress() -> (stepIndex: Int, wasActive: Bool)? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: activeKey) else { return nil }
        let stepIndex = max(0, defaults.integer(forKey: stepKey))

        if defaults.integer(forKey: stuckStepKey) == stepIndex {
            let count = defaults.integer(forKey: stuckCountKey) + 1
            defaults.set(count, forKey: stuckCountKey)
            if count > maxStuckRestores {
                // Never trap the user behind a tour that can't get past this step.
                markCompleted()
                return nil
            }
        } else {
            defaults.set(stepIndex, forKey: stuckStepKey)
            defaults.set(1, forKey: stuckCountKey)
        }

        return (stepIndex, true)
    }
}

extension Notification.Name {
    static let replayAppFeatureTour = Notification.Name("lookafter.replayAppFeatureTour")
    /// Posted when the tour needs a scrollable screen to reveal an anchor.
    static let tourScrollToAnchor = Notification.Name("lookafter.tourScrollToAnchor")
}

enum TourScrollUserInfoKey {
    static let anchorID = "anchorID"
    static let offset = "offset"
    /// `"top"` keeps scroll content at the top (Briefing greeting visible); `"center"` centers the anchor.
    static let scrollAnchor = "scrollAnchor"
}

extension AppFeatureTourAnchorID {
    /// How scroll views should reveal this anchor during the tour.
    var tourScrollAnchor: String {
        switch self {
        case .briefingHero: return "top"
        case .briefingHealthStrip: return "center"
        default: return "center"
        }
    }
}
