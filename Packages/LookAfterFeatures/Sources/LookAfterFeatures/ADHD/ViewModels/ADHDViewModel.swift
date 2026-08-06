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
    /// Bumps when Live Activity should refresh progress (bucket boundaries).
    @Published public private(set) var focusProgressBucket: Int = -1

    private static let liveActivityProgressBuckets: Set<Int> = [0, 25, 50, 65, 75, 90, 95]
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
    
    private var focusTickTask: Task<Void, Never>?
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
        cancelCountdownIfNeeded()
        isCountdownActive = true
        countdownValue = 3
        currentFocusTask = task

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }

                if self.countdownValue > 1 {
                    self.countdownValue -= 1
                } else {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.isCountdownActive = false
                    self.countdownValue = 3
                    onComplete()
                }
            }
        }
        countdownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func cancelCountdownIfNeeded() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountdownActive = false
        countdownValue = 3
    }
    
    // MARK: - Focus Session
    
    /// Start a focus/pomodoro session — uses the scheduled window when set, else task estimate.
    /// Performance: flips `isFocusSessionActive` immediately so UI can paint; timer starts next run-loop.
    public func startFocusSession(task: LifeTask, durationMinutes: Int? = nil) {
        PerformanceMonitor.measure("ADHDViewModel.startFocusSession", warnAfterMs: 16) {
            let duration = durationMinutes ?? Self.focusDuration(for: task, defaultMinutes: focusDurationMinutes)
            cancelCountdownIfNeeded()
            stopFocusTick()
            focusSessionElapsed = 0
            focusSessionTarget = TimeInterval(duration * 60)
            focusProgressBucket = -1
            focusBreakReminder = false
            currentFocusTask = task
            isPaused = false
            isOnBreak = false
            showContextRecovery = false
            currentSessionNumber = 1
            // UI flag last so observers see a complete initial state in one publish cycle.
            isFocusSessionActive = true
        }

        Task { @MainActor in
            await Task.yield()
            guard isFocusSessionActive else { return }
            startFocusTimer()
        }
    }

    /// Preferred focus block length — honors fixed schedule windows (e.g. 9h office block).
    public static func focusDuration(for task: LifeTask, defaultMinutes: Int, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: task.scheduledDate ?? task.scheduledTime ?? now)
        if let window = TaskScheduleInterval.window(for: task, on: referenceDay, calendar: calendar) {
            return window.durationMinutes
        }
        if task.estimatedMinutes > 0 {
            return task.estimatedMinutes
        }
        return defaultMinutes
    }
    
    private func stopFocusTick() {
        focusTickTask?.cancel()
        focusTickTask = nil
    }

    private func publishFocusProgressBucketIfNeeded() {
        let bucket = Int((focusProgress * 100).rounded(.down))
        guard Self.liveActivityProgressBuckets.contains(bucket), bucket != focusProgressBucket else { return }
        focusProgressBucket = bucket
    }

    private func startFocusTimer() {
        stopFocusTick()
        focusTickTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, isFocusSessionActive else { return }
                guard !isPaused else { continue }

                focusSessionElapsed += 1
                publishFocusProgressBucketIfNeeded()

                if focusSessionElapsed >= focusSessionTarget {
                    stopFocusTick()
                    if isOnBreak {
                        isOnBreak = false
                        currentSessionNumber += 1
                        if let task = currentFocusTask {
                            startFocusSession(task: task)
                        }
                    } else {
                        startBreak()
                    }
                    return
                }

                if !isOnBreak && focusSessionElapsed > focusSessionTarget * 1.5 {
                    focusBreakReminder = true
                }
            }
        }
    }
    
    /// Start a break period.
    private func startBreak() {
        isOnBreak = true
        focusSessionElapsed = 0
        focusProgressBucket = -1
        
        // Long break every N sessions
        let isLongBreak = currentSessionNumber % sessionsBeforeLongBreak == 0
        focusSessionTarget = TimeInterval((isLongBreak ? longBreakMinutes : breakDurationMinutes) * 60)
        focusBreakReminder = false
        
        startFocusTimer()
    }
    
    /// Pause the focus session.
    public func pauseFocusSession() {
        stopFocusTick()
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
        stopFocusTick()
        isOnBreak = false
        currentSessionNumber += 1
        if let task = currentFocusTask {
            startFocusSession(task: task)
        }
    }
    
    /// Add time to current session.
    public func addTime(minutes: Int) {
        focusSessionTarget += TimeInterval(minutes * 60)
        publishFocusProgressBucketIfNeeded()
    }
    
    /// Reduce time from current session.
    public func reduceTime(minutes: Int) {
        let reduction = TimeInterval(minutes * 60)
        focusSessionTarget = max(focusSessionElapsed + 60, focusSessionTarget - reduction) // Keep at least 1 min remaining
        publishFocusProgressBucketIfNeeded()
    }
    
    /// Reset current session timer to full configured duration.
    public func resetTimer() {
        stopFocusTick()
        focusSessionElapsed = 0
        focusProgressBucket = -1
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

    /// End the focus session and return to the app shell.
    public func endFocusSession() {
        let durationMinutes = max(1, Int(focusSessionElapsed / 60))
        let task = currentFocusTask
        stopFocusTick()
        cancelCountdownIfNeeded()
        isFocusSessionActive = false
        focusSessionElapsed = 0
        focusProgressBucket = -1
        focusBreakReminder = false
        currentFocusTask = nil
        isPaused = false
        isOnBreak = false
        showContextRecovery = false
        currentSessionNumber = 1
        Task { @MainActor in
            await Task.yield()
            onFocusSessionEnded?(durationMinutes, task)
        }
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
        let totalSeconds = Int(remaining)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
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
        stopFocusTick()
        bodyDoublingTimer?.invalidate()
        countdownTimer?.invalidate()
    }
}
