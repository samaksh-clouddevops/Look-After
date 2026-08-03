import Foundation
import LookAfterCore
import LookAfterAI

/// ViewModel for ADHD-specific features: Emergency Mode, Focus Sessions, Body Doubling.
@MainActor
public final class ADHDViewModel: ObservableObject {
    
    // MARK: - Emergency Mode
    
    @Published public var isEmergencyMode: Bool = false
    @Published public var emergencyTasks: [LifeTask] = []
    
    // MARK: - Focus Session
    
    @Published public var isFocusSessionActive: Bool = false
    @Published public var focusSessionElapsed: TimeInterval = 0
    @Published public var focusSessionTarget: TimeInterval = 25 * 60
    @Published public var focusBreakReminder: Bool = false
    @Published public var currentFocusTask: LifeTask?
    @Published public var isPaused: Bool = false
    @Published public var isOnBreak: Bool = false
    @Published public var currentSessionNumber: Int = 1
    
    // User-configurable durations
    @Published public var focusDurationMinutes: Int = 25
    @Published public var breakDurationMinutes: Int = 5
    @Published public var longBreakMinutes: Int = 15
    @Published public var sessionsBeforeLongBreak: Int = 4
    
    // MARK: - Task Initiation
    
    @Published public var isCountdownActive: Bool = false
    @Published public var countdownValue: Int = 3
    
    // MARK: - Body Doubling
    
    @Published public var isBodyDoubling: Bool = false
    @Published public var bodyDoublingElapsed: TimeInterval = 0
    
    // MARK: - Context Recovery
    
    @Published public var lastInterruptedTask: LifeTask?
    @Published public var lastInterruptedTime: Date?
    @Published public var showContextRecovery: Bool = false
    
    // MARK: - Executive Function Score
    
    @Published public var efScore: Int = 50
    @Published public var efScoreTrend: String = "stable" // "improving", "declining", "stable"
    
    private var focusTimer: Timer?
    private var bodyDoublingTimer: Timer?
    private var countdownTimer: Timer?
    private var pausedElapsed: TimeInterval = 0
    
    public init() {
        // Load saved timer settings
        let savedFocus = UserDefaults.standard.integer(forKey: "focusDurationMinutes")
        let savedBreak = UserDefaults.standard.integer(forKey: "breakDurationMinutes")
        let savedLongBreak = UserDefaults.standard.integer(forKey: "longBreakMinutes")
        let savedSessions = UserDefaults.standard.integer(forKey: "sessionsBeforeLongBreak")
        
        if savedFocus > 0 { focusDurationMinutes = savedFocus }
        if savedBreak > 0 { breakDurationMinutes = savedBreak }
        if savedLongBreak > 0 { longBreakMinutes = savedLongBreak }
        if savedSessions > 0 { sessionsBeforeLongBreak = savedSessions }
    }
    
    // MARK: - Emergency Mode
    
    /// Activate emergency mode — shows only top 3 tasks with minimal UI.
    public func activateEmergencyMode(allTasks: [LifeTask]) {
        isEmergencyMode = true
        
        emergencyTasks = Array(
            allTasks
                .filter { $0.status.isActive }
                .sorted { task1, task2 in
                    if task1.isOverdue && !task2.isOverdue { return true }
                    if !task1.isOverdue && task2.isOverdue { return false }
                    if task1.priority != task2.priority { return task1.priority > task2.priority }
                    return task1.estimatedMinutes < task2.estimatedMinutes
                }
                .prefix(3)
        )
    }
    
    public func deactivateEmergencyMode() {
        isEmergencyMode = false
        emergencyTasks = []
    }
    
    // MARK: - Task Initiation Countdown
    
    /// 3-2-1 countdown to help overcome task initiation resistance.
    public func startCountdown(for task: LifeTask, onComplete: @escaping () -> Void) {
        isCountdownActive = true
        countdownValue = 3
        currentFocusTask = task
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                
                if self.countdownValue > 1 {
                    self.countdownValue -= 1
                } else {
                    timer.invalidate()
                    self.isCountdownActive = false
                    self.countdownValue = 3
                    onComplete()
                }
            }
        }
    }
    
    // MARK: - Focus Session
    
    /// Start a focus/pomodoro session with user-configured duration.
    public func startFocusSession(task: LifeTask, durationMinutes: Int? = nil) {
        let duration = durationMinutes ?? focusDurationMinutes
        isFocusSessionActive = true
        focusSessionElapsed = 0
        focusSessionTarget = TimeInterval(duration * 60)
        focusBreakReminder = false
        currentFocusTask = task
        isPaused = false
        isOnBreak = false
        
        startFocusTimer()
    }
    
    private func startFocusTimer() {
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                
                self.focusSessionElapsed += 1
                
                // Check if session is complete
                if self.focusSessionElapsed >= self.focusSessionTarget {
                    timer.invalidate()
                    if self.isOnBreak {
                        // Break finished — start next focus session
                        self.isOnBreak = false
                        self.currentSessionNumber += 1
                        self.startFocusSession(task: self.currentFocusTask ?? LifeTask(title: "Working"))
                    } else {
                        // Focus finished — start break
                        self.startBreak()
                    }
                    return
                }
                
                // Check for hyperfocus (past target by 50%) only during focus (not break)
                if !self.isOnBreak && self.focusSessionElapsed > self.focusSessionTarget * 1.5 {
                    self.focusBreakReminder = true
                }
            }
        }
    }
    
    /// Start a break period.
    private func startBreak() {
        isOnBreak = true
        focusSessionElapsed = 0
        
        // Long break every N sessions
        let isLongBreak = currentSessionNumber % sessionsBeforeLongBreak == 0
        focusSessionTarget = TimeInterval((isLongBreak ? longBreakMinutes : breakDurationMinutes) * 60)
        focusBreakReminder = false
        
        startFocusTimer()
    }
    
    /// Pause the focus session.
    public func pauseFocusSession() {
        focusTimer?.invalidate()
        isPaused = true
        pausedElapsed = focusSessionElapsed
        
        // Save context for recovery
        if let task = currentFocusTask {
            lastInterruptedTask = task
            lastInterruptedTime = Date()
            showContextRecovery = true
        }
    }
    
    /// Resume from pause.
    public func resumeFocusSession() {
        isPaused = false
        showContextRecovery = false
        focusSessionElapsed = pausedElapsed
        startFocusTimer()
    }
    
    /// Skip the current break and start next focus session.
    public func skipBreak() {
        guard isOnBreak else { return }
        focusTimer?.invalidate()
        isOnBreak = false
        currentSessionNumber += 1
        if let task = currentFocusTask {
            startFocusSession(task: task)
        }
    }
    
    /// Add time to current session.
    public func addTime(minutes: Int) {
        focusSessionTarget += TimeInterval(minutes * 60)
    }
    
    /// Reduce time from current session.
    public func reduceTime(minutes: Int) {
        let reduction = TimeInterval(minutes * 60)
        focusSessionTarget = max(focusSessionElapsed + 60, focusSessionTarget - reduction) // Keep at least 1 min remaining
    }
    
    /// Reset current session timer to full configured duration.
    public func resetTimer() {
        focusTimer?.invalidate()
        focusSessionElapsed = 0
        if isOnBreak {
            let isLongBreak = currentSessionNumber % sessionsBeforeLongBreak == 0
            focusSessionTarget = TimeInterval((isLongBreak ? longBreakMinutes : breakDurationMinutes) * 60)
        } else {
            focusSessionTarget = TimeInterval(focusDurationMinutes * 60)
        }
        isPaused = false
        startFocusTimer()
    }
    
    /// Optional hook for Flow Director re-orchestration after a focus session ends.
    public var onFocusSessionEnded: ((Int, LifeTask?) -> Void)?

    /// End the focus session.
    public func endFocusSession() {
        let durationMinutes = max(1, Int(focusSessionElapsed / 60))
        let task = currentFocusTask
        focusTimer?.invalidate()
        isFocusSessionActive = false
        focusSessionElapsed = 0
        focusBreakReminder = false
        currentFocusTask = nil
        isPaused = false
        isOnBreak = false
        currentSessionNumber = 1
        onFocusSessionEnded?(durationMinutes, task)
    }
    
    /// Resume from interruption with context recovery.
    public func resumeFromInterruption() {
        showContextRecovery = false
        if let task = lastInterruptedTask {
            startFocusSession(task: task)
        }
    }
    
    // MARK: - Body Doubling
    
    /// Start body doubling mode — virtual co-working presence.
    public func startBodyDoubling() {
        isBodyDoubling = true
        bodyDoublingElapsed = 0
        
        bodyDoublingTimer?.invalidate()
        bodyDoublingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                self.bodyDoublingElapsed += 1
            }
        }
    }
    
    /// End body doubling mode.
    public func endBodyDoubling() {
        bodyDoublingTimer?.invalidate()
        isBodyDoubling = false
        bodyDoublingElapsed = 0
    }
    
    // MARK: - Save Settings
    
    public func saveTimerSettings() {
        UserDefaults.standard.set(focusDurationMinutes, forKey: "focusDurationMinutes")
        UserDefaults.standard.set(breakDurationMinutes, forKey: "breakDurationMinutes")
        UserDefaults.standard.set(longBreakMinutes, forKey: "longBreakMinutes")
        UserDefaults.standard.set(sessionsBeforeLongBreak, forKey: "sessionsBeforeLongBreak")
    }
    
    // MARK: - Computed Properties
    
    /// Formatted elapsed time for focus session.
    public var focusElapsedString: String {
        let minutes = Int(focusSessionElapsed) / 60
        let seconds = Int(focusSessionElapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Formatted remaining time for focus session.
    public var focusRemainingString: String {
        let remaining = max(0, focusSessionTarget - focusSessionElapsed)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Progress fraction for focus session (0.0 to 1.0).
    public var focusProgress: Double {
        guard focusSessionTarget > 0 else { return 0 }
        return min(focusSessionElapsed / focusSessionTarget, 1.0)
    }
    
    /// Current session label (task headline or break name).
    public var sessionLabel: String {
        if isOnBreak {
            let isLongBreak = currentSessionNumber % sessionsBeforeLongBreak == 0
            return isLongBreak ? "Long Break" : "Short Break"
        }
        if let task = currentFocusTask {
            return HumanLanguage.outcomeHeadline(task: task)
        }
        return "Working"
    }
    
    /// Session counter string.
    public var sessionCounterString: String {
        return "Session \(currentSessionNumber) of \(sessionsBeforeLongBreak)"
    }
    
    /// Formatted body doubling elapsed time.
    public var bodyDoublingElapsedString: String {
        let minutes = Int(bodyDoublingElapsed) / 60
        let seconds = Int(bodyDoublingElapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// Time since interruption.
    public var timeSinceInterruption: String? {
        guard let time = lastInterruptedTime else { return nil }
        return time.relativeTimeString
    }
    
    // MARK: - Cleanup
    
    public func cleanup() {
        focusTimer?.invalidate()
        bodyDoublingTimer?.invalidate()
        countdownTimer?.invalidate()
    }
}
