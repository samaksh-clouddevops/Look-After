import Foundation
import SwiftUI
import LookAfterCore

// MARK: - Anchors

enum AppFeatureTourAnchorID: String, Hashable, CaseIterable {
    case tabBriefing
    case tabToday
    case tabCapture
    case tabBrain
    case tabYou
    case briefingHero
    case todayTimeline
    case brainVoiceOrb
    case youProfile
}

enum AppFeatureTourCardPlacement {
    case center
    case aboveTarget
    case belowTarget
}

struct AppFeatureTourStep: Identifiable {
    let id: String
    let title: String
    let message: String
    let icon: String
    let tab: LookAfterTab?
    let anchor: AppFeatureTourAnchorID?
    let placement: AppFeatureTourCardPlacement

    static let all: [AppFeatureTourStep] = [
        AppFeatureTourStep(
            id: "welcome",
            title: "Welcome to Look After",
            message: "This quick tour shows where everything lives. It takes about a minute.",
            icon: "sparkles",
            tab: .briefing,
            anchor: nil,
            placement: .center
        ),
        AppFeatureTourStep(
            id: "briefing",
            title: "Briefing",
            message: "Start here each day. AI summarizes sleep, tasks, and energy in three short points. Scroll down for health, schedule, and insights.",
            icon: "doc.text.fill",
            tab: .briefing,
            anchor: .briefingHero,
            placement: .belowTarget
        ),
        AppFeatureTourStep(
            id: "today",
            title: "Today",
            message: "Your live timeline shows what's happening now. Swipe tasks, start focus sessions, and replan the day from here.",
            icon: "calendar",
            tab: .today,
            anchor: .todayTimeline,
            placement: .belowTarget
        ),
        AppFeatureTourStep(
            id: "assistant",
            title: "Plan With Me",
            message: "The assistant sheet at the bottom helps replan your day. Talk or type — it reshapes your schedule with you.",
            icon: "bubble.left.and.bubble.right.fill",
            tab: .today,
            anchor: .todayTimeline,
            placement: .aboveTarget
        ),
        AppFeatureTourStep(
            id: "capture",
            title: "Capture",
            message: "Tap + anytime to dump a thought, task, or note before you forget. Voice or text — no sorting required.",
            icon: "plus.circle.fill",
            tab: nil,
            anchor: .tabCapture,
            placement: .aboveTarget
        ),
        AppFeatureTourStep(
            id: "brain",
            title: "Executive Brain",
            message: "Talk to your AI companion. Tap the orb to speak, get coaching, or ask it to decide your next move.",
            icon: "brain.head.profile",
            tab: .brain,
            anchor: .brainVoiceOrb,
            placement: .belowTarget
        ),
        AppFeatureTourStep(
            id: "you",
            title: "You",
            message: "Your profile, life modules, inbox, insights, and settings live here. Customize the app to match how you work.",
            icon: "person.fill",
            tab: .you,
            anchor: .youProfile,
            placement: .belowTarget
        ),
        AppFeatureTourStep(
            id: "focus",
            title: "Focus & ADHD tools",
            message: "Start a task to enter focus mode. Use Decide for Me when you're stuck, body doubling, or a physiological reset from the Brain menu.",
            icon: "timer",
            tab: .briefing,
            anchor: nil,
            placement: .center
        ),
        AppFeatureTourStep(
            id: "done",
            title: "You're all set",
            message: "Explore at your own pace. Replay this tour anytime from Settings → Help.",
            icon: "checkmark.circle.fill",
            tab: .briefing,
            anchor: nil,
            placement: .center
        ),
    ]
}

// MARK: - Persistence

enum AppFeatureTourStore {
    private static let completedKey = "lookafter.hasCompletedFeatureTour"

    static var shouldPresent: Bool {
        !UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}

extension Notification.Name {
    static let replayAppFeatureTour = Notification.Name("lookafter.replayAppFeatureTour")
}
