import Foundation
import LookAfterCore
import LookAfterData
import LookAfterFeatures
import LookAfterHealth

/// Overall sync outcome shown in Settings and progress UI.
enum HealthSyncPhase: Equatable {
    case idle
    case syncing
    case complete
    case failed
}

/// Visual status for each step shown during Apple Watch / Health sync.
enum HealthSyncStepStatus: Equatable {
    case pending
    case active
    case done
    case noData
    case failed
}

/// One row in the sync progress checklist.
struct HealthSyncStepItem: Identifiable, Equatable {
    let id: String
    let title: String
    let explanation: String
    let icon: String
    var status: HealthSyncStepStatus
    var detail: String?
}

// MARK: - Post-sync verification

enum HealthVerificationOutcome: Equatable {
    case passed
    case warning
    case failed
}

struct HealthVerificationCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let status: HealthVerificationOutcome
    let value: String?
    let issue: String?
    let fixHint: String?
}

struct HealthSyncVerificationReport: Equatable {
    var checks: [HealthVerificationCheck]
    var headline: String
    var summary: String

    var overallPassed: Bool {
        !checks.contains { $0.status == .failed }
    }

    var hasUsableData: Bool {
        checks.contains { $0.status == .passed && $0.value != nil }
    }

    var failedChecks: [HealthVerificationCheck] {
        checks.filter { $0.status == .failed }
    }

    var warningChecks: [HealthVerificationCheck] {
        checks.filter { $0.status == .warning }
    }
}

/// Syncs Apple Watch / HealthKit data into the app's health repository.
/// Apple Watch data flows into iPhone HealthKit automatically; we read from there.
@MainActor
final class HealthSyncService: ObservableObject {
    
    static let shared = HealthSyncService()
    static let setupTimeoutSeconds: TimeInterval = 5
    static let fetchTimeoutSeconds: TimeInterval = 120
    static let saveTimeoutSeconds: TimeInterval = 30
    
    @Published var lastSyncDate: Date?
    @Published var syncMessage: String?
    @Published var isSyncing = false
    @Published var isConnectingForSetup = false
    @Published var deferredToBackground = false
    @Published var setupStatusMessage: String?
    @Published var syncSteps: [HealthSyncStepItem] = []
    @Published var currentStepLabel: String?
    @Published var syncPhase: HealthSyncPhase = .idle
    @Published var lastSyncError: String?
    @Published private(set) var importedMetricCount: Int = 0
    @Published private(set) var verificationReport: HealthSyncVerificationReport?
    @Published private(set) var connectionStatus: HealthConnectionStatus?
    
    private let healthManager = HealthManager()
    private let healthRepo = HealthSummaryRepository()
    private var backgroundSyncTask: Task<Void, Never>?
    private var observerSyncTask: Task<Void, Never>?
    private var lastObserverSyncAt: Date?
    
    private init() {
        lastSyncDate = UserDefaults.standard.object(forKey: "healthLastSyncDate") as? Date
        refreshConnectionStatus(userId: "", healthSummary: HealthStore.shared.latest)
    }

    /// Recomputes user-facing connection status from current sync state and cached summary.
    func refreshConnectionStatus(userId: String, healthSummary: HealthSummary? = nil) {
        if UITestLaunchConfiguration.isEnabled,
           let mock = UserDefaults.standard.string(forKey: "uitest_mock_health_status") {
            connectionStatus = Self.uitestMockConnectionStatus(kind: mock)
            return
        }

        let summary = healthSummary ?? HealthStore.shared.latest
        let authorizePassed = verificationReport?.checks.first(where: { $0.id == "authorize" })?.status == .passed
        let authorizationGranted: Bool? = {
            if authorizePassed { return true }
            if verificationReport?.checks.first(where: { $0.id == "authorize" })?.status == .failed {
                return false
            }
            if healthManager.isAuthorized { return true }
            if lastSyncDate != nil, importedMetricCount > 0 { return true }
            return nil
        }()

        let input = HealthConnectionStatusInput.from(
            summary: summary,
            isHealthEnabled: isHealthEnabled,
            isHealthKitAvailable: isAvailable,
            isSignedIn: !userId.isEmpty,
            lastSyncDate: lastSyncDate,
            authorizationGranted: authorizationGranted
        )
        connectionStatus = HealthConnectionStatusResolver.resolve(input)
    }

    /// Registers HealthKit background observers — call once after onboarding / when health is enabled.
    func startHealthObservers() {
        HealthKitObserverService.shared.startObserving()
    }

    /// Debounced sync triggered by HealthKit observer callbacks.
    /// `onComplete` runs after the sync attempt (or immediately when throttled).
    func scheduleObserverSync(userId: String, onComplete: (() async -> Void)? = nil) {
        guard isHealthEnabled, !userId.isEmpty else {
            if let onComplete {
                Task { await onComplete() }
            }
            return
        }
        observerSyncTask?.cancel()
        observerSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if let last = self.lastObserverSyncAt, Date().timeIntervalSince(last) < 60 {
                await onComplete?()
                return
            }
            self.lastObserverSyncAt = Date()
            await self.syncHealthData(userId: userId)
            await onComplete?()
        }
    }

    /// Waits until an in-flight sync or connect finishes.
    func waitUntilIdle() async {
        while isSyncing || isConnectingForSetup {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
        }
    }

    /// Ensures health data is synced before brain/UI refresh — skips if recently synced.
    func ensureSynced(userId: String, maxAgeSeconds: TimeInterval = 30 * 60) async {
        guard isHealthEnabled, !userId.isEmpty, healthManager.isAvailable else { return }

        if isSyncing || isConnectingForSetup {
            await waitUntilIdle()
            return
        }

        if syncPhase == .complete,
           let lastSyncDate,
           Date().timeIntervalSince(lastSyncDate) < maxAgeSeconds {
            return
        }

        await syncHealthData(userId: userId)
    }
    
    var isHealthEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true
    }

    var isAvailable: Bool {
        healthManager.isAvailable
    }
    
    var completedStepCount: Int {
        syncSteps.filter { $0.status == .done || $0.status == .noData }.count
    }
    
    var totalStepCount: Int { syncSteps.count }
    
    var activeStep: HealthSyncStepItem? {
        syncSteps.first { $0.status == .active }
    }
    
    var canRetry: Bool {
        syncPhase == .failed && !isSyncing
    }
    
    /// Resets stale sync UI so a new user-initiated connect always shows feedback.
    func prepareForUserConnect() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
        isSyncing = false
        isConnectingForSetup = false
        syncPhase = .idle
        syncSteps = []
        lastSyncError = nil
        setupStatusMessage = nil
        importedMetricCount = 0
        verificationReport = nil
        connectionStatus = nil
    }

    /// User-facing connect — waits for the full HealthKit import so the sheet shows real progress.
    func connectHealthDuringSetup(userId: String, forceAuthorizationPrompt: Bool = false) async {
        prepareForUserConnect()
        guard isHealthEnabled else {
            let message = "Health tracking is disabled in Settings."
            verificationReport = Self.verificationFailureReport(
                headline: "Health tracking off",
                summary: message,
                checks: [Self.failedCheck(id: "enabled", title: "Health tracking", icon: "heart.slash.fill", issue: message, fix: "Turn on Health Tracking in Settings → Features.")]
            )
            setupStatusMessage = message
            syncMessage = message
            syncPhase = .failed
            lastSyncError = message
            return
        }

        guard healthManager.isAvailable else {
            let message = "HealthKit is not available on this device."
            verificationReport = Self.verificationFailureReport(
                headline: "HealthKit unavailable",
                summary: message,
                checks: [Self.failedCheck(id: "available", title: "HealthKit", icon: "heart.slash.fill", issue: message, fix: "Use a physical iPhone — HealthKit is not available in Simulator for all data types.")]
            )
            setupStatusMessage = message
            syncMessage = message
            syncPhase = .failed
            lastSyncError = message
            return
        }

        guard !userId.isEmpty else {
            let message = "Sign in to sync health data."
            verificationReport = Self.verificationFailureReport(
                headline: "Not signed in",
                summary: message,
                checks: [Self.failedCheck(id: "user", title: "Account", icon: "person.crop.circle.badge.exclamationmark", issue: message, fix: "Sign in, then tap Connect Health again.")]
            )
            setupStatusMessage = message
            syncMessage = message
            syncPhase = .failed
            lastSyncError = message
            return
        }

        isConnectingForSetup = true
        deferredToBackground = false
        setupStatusMessage = "Allow access in the Apple Health dialog…"
        syncMessage = nil
        lastSyncError = nil
        syncSteps = Self.makeSetupSteps()
        currentStepLabel = "Connecting Health…"
        updateStep(id: "connect", status: .active, detail: "Waiting for Apple Health permission")

        defer {
            isConnectingForSetup = false
            refreshConnectionStatus(userId: userId)
        }

        do {
            let authorized = try await requestHealthAccessIfNeeded(forcePrompt: forceAuthorizationPrompt)

            updateStep(id: "connect", status: .done, detail: authorized ? "Health access granted" : "Permission dialog dismissed")
            currentStepLabel = authorized ? "Connected to Health" : "Health access not granted"

            if !authorized {
                let message = "Could not verify Health access. Tap Retry or enable in Settings → Health → \(UserFacingCopy.productName)."
                verificationReport = Self.verificationFailureReport(
                    headline: "Permission not granted",
                    summary: message,
                    checks: [Self.failedCheck(id: "authorize", title: "Apple Health access", icon: "hand.raised.slash.fill", issue: message, fix: "Open Health → Sharing → Apps → \(UserFacingCopy.productName) and turn on Sleep, Steps, and Heart Rate.")]
                )
                setupStatusMessage = message
                syncMessage = message
                syncPhase = .failed
                lastSyncError = message
                return
            }

            setupStatusMessage = "Reading your latest sleep and activity…"
            await performFullSync(userId: userId, triggeredFromSetup: true)
        } catch {
            updateStep(id: "connect", status: .failed, detail: error.localizedDescription)
            setupStatusMessage = error.localizedDescription
            syncMessage = setupStatusMessage
            syncPhase = .failed
            lastSyncError = error.localizedDescription
            currentStepLabel = "Connection failed"
        }
    }

    /// Background connect for app bootstrap — does not block the UI.
    func connectHealthInBackground(userId: String) {
        startBackgroundSync(userId: userId)
    }
    
    /// Full sync for Settings or explicit refresh. Does not block app navigation.
    func syncHealthData(userId: String) async {
        backgroundSyncTask?.cancel()
        await performFullSync(userId: userId, triggeredFromSetup: false)
    }
    
    func retrySync(userId: String) {
        guard canRetry else { return }
        Task {
            await syncHealthData(userId: userId)
        }
    }
    
    func cancelSync() {
        HealthSyncLogger.log("Cancel requested")
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
        isSyncing = false
        syncPhase = .failed
        lastSyncError = "Sync cancelled."
        currentStepLabel = "Sync cancelled"
        if let active = activeStep {
            updateStep(id: active.id, status: .failed, detail: "Cancelled")
        }
    }
    
    func startBackgroundSync(userId: String) {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.performFullSync(userId: userId, triggeredFromSetup: true)
        }
    }
    
    // MARK: - Private sync
    
    private func performFullSync(userId: String, triggeredFromSetup: Bool) async {
        let healthSignpost = PerformanceSignposts.beginHealthSync()
        defer { PerformanceSignposts.endHealthSync(healthSignpost) }
        defer { refreshConnectionStatus(userId: userId) }
        guard isHealthEnabled else {
            failSync(message: "Health tracking is disabled in Settings.", stepId: "prepare")
            syncSteps = []
            currentStepLabel = nil
            return
        }
        
        guard healthManager.isAvailable else {
            failSync(message: "HealthKit is not available on this device.", stepId: "prepare")
            syncSteps = []
            currentStepLabel = nil
            return
        }
        
        isSyncing = true
        syncPhase = .syncing
        lastSyncError = nil
        if !triggeredFromSetup {
            syncMessage = nil
        }
        syncSteps = Self.makeInitialSteps()
        updateStep(id: "prepare", status: .active, detail: "Checking this iPhone can read Apple Health")
        currentStepLabel = triggeredFromSetup ? "Reading Apple Health…" : "Connecting Health…"
        
        defer {
            isSyncing = false
            HealthSyncLogger.finished()
        }
        
        HealthSyncLogger.started()
        
        if Task.isCancelled {
            markCancelled()
            return
        }
        
        do {
            try await HealthSyncLogger.measure("Prepare") {
                updateStep(id: "prepare", status: .done, detail: "HealthKit is available")
            }
            
            updateStep(id: "authorize", status: .active, detail: "Verifying read access")
            currentStepLabel = "Verifying Health access…"
            
            let authorized = try await HealthSyncLogger.measure("Authorization verified") {
                try await requestHealthAccessIfNeeded()
            }
            
            guard authorized else {
                let message = "Health access denied. Enable in Settings → Health → \(UserFacingCopy.productName)."
                updateStep(id: "authorize", status: .noData, detail: message)
                verificationReport = Self.verificationFailureReport(
                    headline: "Permission not granted",
                    summary: message,
                    checks: [Self.failedCheck(id: "authorize", title: "Apple Health access", icon: "hand.raised.slash.fill", issue: message, fix: "Open Health → Sharing → Apps → \(UserFacingCopy.productName) and turn on Sleep, Steps, and Heart Rate.")]
                )
                failSync(message: message, stepId: "authorize")
                return
            }
            updateStep(id: "authorize", status: .done, detail: "Can read sleep, heart rate, steps & workouts")
            
            if Task.isCancelled {
                markCancelled()
                return
            }
            
            updateStep(id: "fetch", status: .active, detail: "Reading data from iPhone Health (includes Apple Watch when paired)")
            currentStepLabel = "Reading Apple Health…"
            
            var summary = try await HealthSyncLogger.measure("Reading health data") {
                try await withTimeout(seconds: Self.fetchTimeoutSeconds) {
                    try await self.healthManager.fetchTodaysSummary { [weak self] event in
                        self?.handleFetchEvent(event)
                    }
                }
            }
            
            updateStep(id: "fetch", status: .done, detail: "All health categories checked")
            
            if Task.isCancelled {
                markCancelled()
                return
            }
            
            currentStepLabel = "Calculating energy score…"
            updateStep(id: "save", status: .active, detail: "Building energy model from sleep, HRV & activity")
            
            try await HealthSyncLogger.measure("Building energy model") {
                summary.userId = userId
                summary.id = HealthSummaryRepository.dailyDocumentId(for: summary.date, userId: userId)
                summary = Self.enrichSummary(summary)
            }

            importedMetricCount = Self.countImportedMetrics(summary)
            
            currentStepLabel = "Uploading to \(UserFacingCopy.productName)…"
            updateStep(id: "save", status: .active, detail: "Saving locally and uploading to \(UserFacingCopy.productName)")
            
            let summaryToSave = summary
            try await HealthSyncLogger.measure("Uploading to \(UserFacingCopy.productName)") {
                try await withTimeout(seconds: Self.saveTimeoutSeconds) {
                    try await self.healthRepo.save(summaryToSave)
                }
            }
            HealthStore.shared.applySaved(summaryToSave)
            
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "healthLastSyncDate")
            
            updateStep(id: "save", status: .done, detail: "Saved for brain & task recommendations")

            currentStepLabel = "Verifying import…"
            updateStep(id: "verify", status: .active, detail: "Checking \(UserFacingCopy.productName) can read saved health data")

            let report = await buildVerificationReport(userId: userId, fetched: summary)
            verificationReport = report

            if report.overallPassed && report.hasUsableData {
                updateStep(id: "verify", status: .done, detail: report.summary)
            } else if report.hasUsableData {
                updateStep(id: "verify", status: .noData, detail: report.summary)
            } else {
                updateStep(id: "verify", status: .failed, detail: report.summary)
            }

            currentStepLabel = report.hasUsableData ? "Verification passed" : "Verification found issues"
            deferredToBackground = false
            syncPhase = report.hasUsableData ? .complete : .failed
            if !report.hasUsableData {
                lastSyncError = report.summary
            }
            syncMessage = report.summary
            refreshConnectionStatus(userId: userId, healthSummary: summaryToSave)
            HealthSyncLogger.log("Database write completed")
            await syncCycleFromHealthKitIfEnabled()
            NotificationCenter.default.post(
                name: .analyticsDataDidChange,
                object: nil,
                userInfo: ["reason": AnalyticsDataChangeReason.healthSyncCompleted.rawValue]
            )
        } catch is HealthSyncTimeoutError {
            handleSyncFailure(
                error: HealthSyncTimeoutError(),
                userMessage: "Sync timed out. Check your connection and try again.",
                stepId: activeStep?.id ?? "save"
            )
        } catch {
            if Task.isCancelled {
                markCancelled()
                return
            }
            handleSyncFailure(error: error, userMessage: error.localizedDescription, stepId: activeStep?.id ?? "save")
        }
    }
    
    private func requestHealthAccessIfNeeded(forcePrompt: Bool = false) async throws -> Bool {
        if healthManager.isAuthorized && !forcePrompt {
            return await healthManager.verifyReadAccess()
        }
        if forcePrompt {
            healthManager.resetAuthorizationPrompt()
        }
        return try await healthManager.requestAuthorization()
    }
    
    private struct HealthSyncTimeoutError: Error, LocalizedError {
        var errorDescription: String? { "The operation timed out." }
    }
    
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HealthSyncTimeoutError()
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw HealthSyncTimeoutError()
            }
            return value
        }
    }
    
    private func markCancelled() {
        HealthSyncLogger.cancelled("Sync")
        syncPhase = .failed
        lastSyncError = "Sync cancelled."
        currentStepLabel = "Sync cancelled"
        if let active = activeStep {
            updateStep(id: active.id, status: .failed, detail: "Cancelled")
        }
    }
    
    private func failSync(message: String, stepId: String) {
        syncPhase = .failed
        lastSyncError = message
        currentStepLabel = "Sync Failed"
        syncMessage = message
        updateStep(id: stepId, status: .failed, detail: message)
        HealthSyncLogger.log("Failed: \(message)")
    }
    
    private func handleSyncFailure(error: Error, userMessage: String, stepId: String) {
        updateStep(id: stepId, status: .failed, detail: userMessage)
        syncPhase = .failed
        lastSyncError = userMessage
        currentStepLabel = "Sync Failed (Retry)"
        if syncMessage == nil {
            syncMessage = userMessage
        }
        HealthSyncLogger.stageFailure("Sync", duration: 0, error: error)
    }
    
    // MARK: - Step helpers
    
    private static func makeSetupSteps() -> [HealthSyncStepItem] {
        [
            HealthSyncStepItem(
                id: "connect",
                title: "Connect Health",
                explanation: "\(UserFacingCopy.productName) reads sleep, heart rate, and activity from Apple Health",
                icon: "heart.text.square.fill",
                status: .pending,
                detail: nil
            ),
        ]
    }
    
    private static func makeInitialSteps() -> [HealthSyncStepItem] {
        var steps: [HealthSyncStepItem] = [
            HealthSyncStepItem(
                id: "prepare",
                title: "Connect to Apple Health",
                explanation: "Apple Watch data syncs to iPhone Health automatically when paired",
                icon: "heart.text.square.fill",
                status: .pending,
                detail: nil
            ),
            HealthSyncStepItem(
                id: "authorize",
                title: "Grant read access",
                explanation: "\(UserFacingCopy.productName) only reads — it never writes to Health",
                icon: "hand.raised.fill",
                status: .pending,
                detail: nil
            ),
            HealthSyncStepItem(
                id: "fetch",
                title: "Read health data",
                explanation: "Pulling sleep, heart, activity & workouts from Health",
                icon: "applewatch.watchface",
                status: .pending,
                detail: nil
            ),
        ]
        
        for fetchStep in HealthFetchStep.allCases {
            steps.append(
                HealthSyncStepItem(
                    id: fetchStep.rawValue,
                    title: fetchStep.title,
                    explanation: fetchStep.explanation,
                    icon: fetchStep.icon,
                    status: .pending,
                    detail: nil
                )
            )
        }
        
        steps.append(
            HealthSyncStepItem(
                id: "save",
                title: "Save to \(UserFacingCopy.productName)",
                explanation: "Uses this data to estimate energy & personalize tasks",
                icon: "square.and.arrow.down.fill",
                status: .pending,
                detail: nil
            )
        )

        steps.append(
            HealthSyncStepItem(
                id: "verify",
                title: "Verify import",
                explanation: "Confirms saved data will appear on Today",
                icon: "checkmark.shield.fill",
                status: .pending,
                detail: nil
            )
        )

        return steps
    }
    
    private func handleFetchEvent(_ event: HealthFetchEvent) {
        switch event {
        case .started(let step):
            updateStep(id: step.rawValue, status: .active, detail: step.explanation)
            if step == .sleep {
                currentStepLabel = "Processing sleep data…"
            } else {
                currentStepLabel = step.explanation
            }
        case .completed(let step, let detail):
            updateStep(id: step.rawValue, status: .done, detail: detail)
        case .noData(let step, let detail):
            updateStep(id: step.rawValue, status: .noData, detail: detail)
        case .failed(let step, let error):
            updateStep(id: step.rawValue, status: .failed, detail: error)
        }
    }
    
    private func updateStep(id: String, status: HealthSyncStepStatus, detail: String?) {
        guard let index = syncSteps.firstIndex(where: { $0.id == id }) else { return }
        syncSteps[index].status = status
        if let detail {
            syncSteps[index].detail = detail
        }
    }
    
    private static func enrichSummary(_ summary: HealthSummary) -> HealthSummary {
        var enriched = summary
        if enriched.sleepQualityScore == nil, let sleep = enriched.totalSleepMinutes, sleep > 0 {
            let normalized = min(max(sleep / (8 * 60), 0), 1)
            enriched.sleepQualityScore = normalized
        }
        return enriched
    }
    
    private static func dailySummaryId(for date: Date, userId: String) -> String {
        let day = Calendar.current.startOfDay(for: date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dayKey = formatter.string(from: day)
        return userId.isEmpty ? dayKey : "\(userId)-\(dayKey)"
    }

    private static func countImportedMetrics(_ summary: HealthSummary) -> Int {
        var count = 0
        if (summary.totalSleepMinutes ?? 0) > 0 { count += 1 }
        if summary.restingHeartRate != nil || summary.averageHeartRate != nil { count += 1 }
        if summary.hrvAverage != nil { count += 1 }
        if (summary.stepCount ?? 0) > 0 { count += 1 }
        if (summary.workoutCount ?? 0) > 0 { count += 1 }
        return count
    }

    private static func summaryMessage(from summary: HealthSummary, importedMetricCount: Int) -> String {
        if importedMetricCount == 0 {
            return """
            Connected to Apple Health, but no sleep or activity was returned. \
            Open the Health app → Sharing → Apps → \(UserFacingCopy.productName) and turn on Sleep, Steps, and Heart Rate.
            """
        }

        var parts: [String] = []
        if let sleep = summary.totalSleepMinutes, sleep > 0 {
            parts.append("\(String(format: "%.1f", sleep / 60))h sleep")
        }
        if let hrv = summary.hrvAverage {
            parts.append("HRV \(Int(hrv))ms")
        }
        if let steps = summary.stepCount, steps > 0 {
            parts.append("\(steps) steps")
        }
        if let hr = summary.restingHeartRate {
            parts.append("RHR \(Int(hr)) bpm")
        }
        
        if parts.isEmpty {
            return "Connected to Health. Categories checked — some had no samples for today yet."
        }
        return "Imported: \(parts.joined(separator: " • "))"
    }

    // MARK: - Verification

    private func buildVerificationReport(userId: String, fetched: HealthSummary) async -> HealthSyncVerificationReport {
        var checks: [HealthVerificationCheck] = []

        let authorizeStep = syncSteps.first { $0.id == "authorize" }
        if authorizeStep?.status == .done {
            checks.append(HealthVerificationCheck(
                id: "authorize",
                title: "Apple Health permission",
                icon: "hand.raised.fill",
                status: .passed,
                value: "Read access granted",
                issue: nil,
                fixHint: nil
            ))
        } else {
            checks.append(Self.failedCheck(
                id: "authorize",
                title: "Apple Health permission",
                icon: "hand.raised.slash.fill",
                issue: authorizeStep?.detail ?? "Health access was not granted.",
                fix: "Open Health → Sharing → Apps → \(UserFacingCopy.productName) and enable Sleep, Steps, and Heart Rate."
            ))
        }

        checks.append(verificationCheckForFetchStep(
            id: HealthFetchStep.sleep.rawValue,
            title: "Sleep in Apple Health",
            icon: "bed.double.fill",
            hasData: (fetched.totalSleepMinutes ?? 0) > 0,
            value: fetched.totalSleepMinutes.map { String(format: "%.1fh imported", $0 / 60) },
            emptyIssue: "No sleep found for last night in Apple Health.",
            emptyFix: "Wear your Apple Watch overnight, or turn on Sleep in Health → Sharing → Apps → \(UserFacingCopy.productName)."
        ))

        checks.append(verificationCheckForFetchStep(
            id: HealthFetchStep.activity.rawValue,
            title: "Steps & activity",
            icon: "figure.walk",
            hasData: (fetched.stepCount ?? 0) > 0,
            value: fetched.stepCount.map { "\($0) steps imported" },
            emptyIssue: "No steps recorded today in Apple Health.",
            emptyFix: "Walk with your iPhone or Apple Watch, or open Health → Sharing → Apps → \(UserFacingCopy.productName) and enable Steps and Activity."
        ))

        checks.append(verificationCheckForFetchStep(
            id: HealthFetchStep.heartRate.rawValue,
            title: "Heart rate",
            icon: "heart.fill",
            hasData: fetched.restingHeartRate != nil || fetched.averageHeartRate != nil,
            value: Self.heartRateVerificationValue(fetched),
            emptyIssue: "No heart rate samples today.",
            emptyFix: "Enable Heart Rate in Health → Sharing → Apps → \(UserFacingCopy.productName), or wear your Watch."
        ))

        checks.append(verificationCheckForFetchStep(
            id: HealthFetchStep.hrv.rawValue,
            title: "HRV (recovery)",
            icon: "waveform.path.ecg",
            hasData: fetched.hrvAverage != nil,
            value: fetched.hrvAverage.map { "\(Int($0)) ms imported" },
            emptyIssue: "No HRV reading today — optional but improves recovery insights.",
            emptyFix: "Wear Apple Watch during sleep; enable Heart Rate Variability in Health sharing."
        ))

        let stored = try? await healthRepo.getLatest(for: userId)
        if let stored, Self.countImportedMetrics(stored) > 0 {
            checks.append(HealthVerificationCheck(
                id: "storage",
                title: "Saved inside \(UserFacingCopy.productName)",
                icon: "internaldrive.fill",
                status: .passed,
                value: Self.summaryMessage(from: stored, importedMetricCount: Self.countImportedMetrics(stored)),
                issue: nil,
                fixHint: nil
            ))
        } else {
            checks.append(Self.failedCheck(
                id: "storage",
                title: "Saved inside \(UserFacingCopy.productName)",
                icon: "internaldrive.fill",
                issue: "Health data did not persist locally after sync.",
                fix: "Tap Retry Connection. If this keeps happening, sign out and back in."
            ))
        }

        let todayReady = stored.map { Self.countImportedMetrics($0) > 0 } ?? false
        if todayReady {
            checks.append(HealthVerificationCheck(
                id: "today",
                title: "Ready for Today screen",
                icon: "sun.max.fill",
                status: .passed,
                value: "Sleep and activity will show after you close this sheet",
                issue: nil,
                fixHint: nil
            ))
        } else {
            checks.append(Self.failedCheck(
                id: "today",
                title: "Ready for Today screen",
                icon: "sun.max.fill",
                issue: "Today cannot show health tiles until sleep or activity is imported.",
                fix: "Fix the issues above, then tap Retry Connection."
            ))
        }

        let passed = checks.filter { $0.status == .passed }.count
        let warnings = checks.filter { $0.status == .warning }.count
        let failures = checks.filter { $0.status == .failed }.count

        let headline: String
        if failures > 0 {
            headline = "Verification failed"
        } else if warnings > 0 {
            headline = "Partially verified"
        } else {
            headline = "All checks passed"
        }

        let summary: String
        if todayReady {
            summary = "Verified \(passed) of \(checks.count) checks — data is ready for Today."
        } else if failures > 0 {
            summary = "\(failures) issue(s) found. See details below."
        } else {
            summary = "Connected but some optional metrics are missing."
        }

        return HealthSyncVerificationReport(checks: checks, headline: headline, summary: summary)
    }

    private func verificationCheckForFetchStep(
        id: String,
        title: String,
        icon: String,
        hasData: Bool,
        value: String?,
        emptyIssue: String,
        emptyFix: String
    ) -> HealthVerificationCheck {
        let step = syncSteps.first { $0.id == id }
        if hasData, let value {
            return HealthVerificationCheck(
                id: id,
                title: title,
                icon: icon,
                status: .passed,
                value: value,
                issue: nil,
                fixHint: nil
            )
        }
        if step?.status == .failed {
            return Self.failedCheck(
                id: id,
                title: title,
                icon: icon,
                issue: step?.detail ?? "Failed to read from Apple Health.",
                fix: emptyFix
            )
        }
        return HealthVerificationCheck(
            id: id,
            title: title,
            icon: icon,
            status: .warning,
            value: nil,
            issue: step?.detail ?? emptyIssue,
            fixHint: emptyFix
        )
    }

    private static func heartRateVerificationValue(_ summary: HealthSummary) -> String? {
        var parts: [String] = []
        if let rhr = summary.restingHeartRate { parts.append("RHR \(Int(rhr)) bpm") }
        if let avg = summary.averageHeartRate { parts.append("avg \(Int(avg)) bpm") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func failedCheck(
        id: String,
        title: String,
        icon: String,
        issue: String,
        fix: String
    ) -> HealthVerificationCheck {
        HealthVerificationCheck(
            id: id,
            title: title,
            icon: icon,
            status: .failed,
            value: nil,
            issue: issue,
            fixHint: fix
        )
    }

    private static func verificationFailureReport(
        headline: String,
        summary: String,
        checks: [HealthVerificationCheck]
    ) -> HealthSyncVerificationReport {
        HealthSyncVerificationReport(checks: checks, headline: headline, summary: summary)
    }

    private func syncCycleFromHealthKitIfEnabled() async {
        guard CycleFeatureGate.isActive else { return }
        guard CyclePreferencesStore.load().usesHealthKit else { return }
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -120, to: Date()) else { return }
        do {
            let logs = try await healthManager.fetchMenstrualSamples(from: start, to: Date())
            CycleLogStore.mergeHealthKitLogs(logs, calendar: calendar)
        } catch {
            HealthSyncLogger.log("Cycle HealthKit sync skipped: \(error.localizedDescription)")
        }
    }

    /// Clears cached sync metadata so the next launch performs a full HealthKit import.
    func resetForFactoryReset() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil
        lastSyncDate = nil
        syncMessage = nil
        isSyncing = false
        isConnectingForSetup = false
        deferredToBackground = false
        setupStatusMessage = nil
        syncSteps = []
        currentStepLabel = nil
        syncPhase = .idle
        lastSyncError = nil
        importedMetricCount = 0
        verificationReport = nil
        UserDefaults.standard.removeObject(forKey: "healthLastSyncDate")
        connectionStatus = nil
    }

    /// Preset resolver inputs for UI tests (`-MockHealthStatus waitingForData|notSetUp`).
    private static func uitestMockConnectionStatus(kind raw: String) -> HealthConnectionStatus {
        let now = Date()
        let input: HealthConnectionStatusInput
        switch raw {
        case "waitingForData":
            input = HealthConnectionStatusInput(
                isHealthEnabled: true,
                isHealthKitAvailable: true,
                isSignedIn: true,
                lastSyncDate: now,
                authorizationGranted: true,
                hasAnyImportedMetrics: false,
                now: now
            )
        case "notSetUp":
            input = HealthConnectionStatusInput(
                isHealthEnabled: true,
                isHealthKitAvailable: true,
                isSignedIn: true,
                authorizationGranted: nil,
                now: now
            )
        case "accessBlocked":
            input = HealthConnectionStatusInput(
                isHealthEnabled: true,
                isHealthKitAvailable: true,
                isSignedIn: true,
                lastSyncDate: now,
                authorizationGranted: false,
                now: now
            )
        default:
            input = HealthConnectionStatusInput(
                isHealthEnabled: true,
                isHealthKitAvailable: true,
                isSignedIn: true,
                now: now
            )
        }
        return HealthConnectionStatusResolver.resolve(input)
    }
}
