import SwiftUI
import LookAfterCore

/// macOS Productivity Tracker — background app/window monitoring & idle detection.
/// Sends productivity logs to Firebase so the AI Executive Brain has full context on Mac usage.
@MainActor
public final class MacProductivityTracker: ObservableObject {
    
    @Published public var isTracking: Bool = false
    @Published public var currentActiveApp: String = "Unknown"
    @Published public var currentWindowTitle: String = "Unknown"
    @Published public var isIdle: Bool = false
    @Published public var todayFocusMinutes: Int = 0
    
    private var trackingTimer: Timer?
    private var lastActivityTime: Date = Date()
    private let idleThresholdSeconds: TimeInterval = 300 // 5 minutes idle
    
    public init() {}
    
    /// Start tracking active application and window.
    public func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        #if os(macOS)
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollActiveApplication()
            }
        }
        #endif
    }
    
    /// Stop tracking.
    public func stopTracking() {
        trackingTimer?.invalidate()
        isTracking = false
    }
    
    #if os(macOS)
    private func pollActiveApplication() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        
        let appName = frontApp.localizedName ?? "Unknown"
        self.currentActiveApp = appName
        
        // Categorize app
        let category = categorizeApp(appName)
        if category == .deepWork || category == .creative {
            todayFocusMinutes += 1 // approximate increment for display
        }
    }
    
    private func categorizeApp(_ appName: String) -> ProductivityCategory {
        let lower = appName.lowercased()
        if lower.contains("xcode") || lower.contains("vs code") || lower.contains("terminal") || lower.contains("github") || lower.contains("sublime") {
            return .deepWork
        } else if lower.contains("slack") || lower.contains("mail") || lower.contains("messages") || lower.contains("teams") || lower.contains("zoom") {
            return .communication
        } else if lower.contains("safari") || lower.contains("chrome") || lower.contains("arc") || lower.contains("firefox") {
            return .neutral
        } else if lower.contains("logic") || lower.contains("ableton") || lower.contains("figma") || lower.contains("photoshop") || lower.contains("sketch") {
            return .creative
        } else if lower.contains("spotify") || lower.contains("music") || lower.contains("youtube") || lower.contains("netflix") {
            return .entertainment
        }
        return .neutral
    }
    #endif
}
