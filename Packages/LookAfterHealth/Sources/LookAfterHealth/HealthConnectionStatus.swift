import Foundation
import LookAfterCore

// MARK: - User-facing health connection status

public enum HealthConnectionKind: String, Sendable, Equatable, CaseIterable {
    case notSetUp
    case accessBlocked
    case trackingOff
    case waitingForData
    case partialData
    case syncStale
    case allGood
}

public enum HealthStatusAction: String, Sendable, Equatable {
    case connect
    case openHealth
    case syncNow
    case openAppSettings
    case none
}

public struct HealthConnectionStatus: Sendable, Equatable {
    public var kind: HealthConnectionKind
    public var headline: String
    public var explanation: String
    public var primaryAction: HealthStatusAction
    public var primaryActionLabel: String
    public var fixSteps: [String]
    public var missingMetrics: [String]

    public init(
        kind: HealthConnectionKind,
        headline: String,
        explanation: String,
        primaryAction: HealthStatusAction,
        primaryActionLabel: String,
        fixSteps: [String] = [],
        missingMetrics: [String] = []
    ) {
        self.kind = kind
        self.headline = headline
        self.explanation = explanation
        self.primaryAction = primaryAction
        self.primaryActionLabel = primaryActionLabel
        self.fixSteps = fixSteps
        self.missingMetrics = missingMetrics
    }

    public var needsAttention: Bool {
        kind != .allGood
    }
}

// MARK: - Resolver input

public struct HealthConnectionStatusInput: Sendable, Equatable {
    public var isHealthEnabled: Bool
    public var isHealthKitAvailable: Bool
    public var isSignedIn: Bool
    public var lastSyncDate: Date?
    /// `nil` when authorization has not been checked yet.
    public var authorizationGranted: Bool?
    public var hasSleepData: Bool
    public var hasActivityData: Bool
    public var hasHeartRateData: Bool
    public var hasHRVData: Bool
    public var hasAnyImportedMetrics: Bool
    public var now: Date
    public var staleSyncThreshold: TimeInterval

    public init(
        isHealthEnabled: Bool,
        isHealthKitAvailable: Bool,
        isSignedIn: Bool,
        lastSyncDate: Date? = nil,
        authorizationGranted: Bool? = nil,
        hasSleepData: Bool = false,
        hasActivityData: Bool = false,
        hasHeartRateData: Bool = false,
        hasHRVData: Bool = false,
        hasAnyImportedMetrics: Bool = false,
        now: Date = Date(),
        staleSyncThreshold: TimeInterval = 24 * 60 * 60
    ) {
        self.isHealthEnabled = isHealthEnabled
        self.isHealthKitAvailable = isHealthKitAvailable
        self.isSignedIn = isSignedIn
        self.lastSyncDate = lastSyncDate
        self.authorizationGranted = authorizationGranted
        self.hasSleepData = hasSleepData
        self.hasActivityData = hasActivityData
        self.hasHeartRateData = hasHeartRateData
        self.hasHRVData = hasHRVData
        self.hasAnyImportedMetrics = hasAnyImportedMetrics
        self.now = now
        self.staleSyncThreshold = staleSyncThreshold
    }

    public static func from(
        summary: HealthSummary?,
        isHealthEnabled: Bool,
        isHealthKitAvailable: Bool,
        isSignedIn: Bool,
        lastSyncDate: Date?,
        authorizationGranted: Bool?,
        now: Date = Date()
    ) -> HealthConnectionStatusInput {
        let hasSleep = (summary?.totalSleepMinutes ?? 0) > 0
        let hasActivity = (summary?.stepCount ?? 0) > 0 || (summary?.workoutCount ?? 0) > 0
        let hasHeart = summary?.restingHeartRate != nil || summary?.averageHeartRate != nil
        let hasHRV = summary?.hrvAverage != nil
        let imported = [hasSleep, hasActivity, hasHeart, hasHRV].filter { $0 }.count

        return HealthConnectionStatusInput(
            isHealthEnabled: isHealthEnabled,
            isHealthKitAvailable: isHealthKitAvailable,
            isSignedIn: isSignedIn,
            lastSyncDate: lastSyncDate,
            authorizationGranted: authorizationGranted,
            hasSleepData: hasSleep,
            hasActivityData: hasActivity,
            hasHeartRateData: hasHeart,
            hasHRVData: hasHRV,
            hasAnyImportedMetrics: imported > 0,
            now: now
        )
    }
}

// MARK: - Resolver

public enum HealthConnectionStatusResolver {
    public static func resolve(_ input: HealthConnectionStatusInput) -> HealthConnectionStatus {
        let product = UserFacingCopy.productName

        if !input.isHealthKitAvailable {
            return HealthConnectionStatus(
                kind: .notSetUp,
                headline: "Health isn't available on this device",
                explanation: "Apple Health data requires a physical iPhone. Simulators can't read Watch or Health data.",
                primaryAction: .none,
                primaryActionLabel: "",
                fixSteps: ["Use Look After on your iPhone to connect Apple Health."]
            )
        }

        if !input.isHealthEnabled {
            return HealthConnectionStatus(
                kind: .trackingOff,
                headline: "Health tracking is turned off",
                explanation: "Look After isn't reading your sleep or activity because Health tracking is disabled in the app.",
                primaryAction: .openAppSettings,
                primaryActionLabel: "Open Settings",
                fixSteps: [
                    "Open Settings in Look After.",
                    "Turn on Health Tracking under Features.",
                    "Tap Sync Apple Watch Data Now."
                ]
            )
        }

        if !input.isSignedIn {
            return HealthConnectionStatus(
                kind: .notSetUp,
                headline: "Sign in to sync Health data",
                explanation: "Your sleep and activity need an account so Look After can save and show them on Today.",
                primaryAction: .connect,
                primaryActionLabel: "Sign in & connect",
                fixSteps: ["Sign in to Look After, then connect Apple Health."]
            )
        }

        if input.authorizationGranted == false {
            return HealthConnectionStatus(
                kind: .accessBlocked,
                headline: "Look After can't read your Health data",
                explanation: "Your iPhone is blocking access. Look After reads from the Health app — it never connects to your Watch directly.",
                primaryAction: .openHealth,
                primaryActionLabel: "Open Health app",
                fixSteps: [
                    "Open the Health app on your iPhone.",
                    "Tap Sharing → Apps → \(product).",
                    "Turn on Sleep, Steps, and Heart Rate."
                ]
            )
        }

        let neverSynced = input.lastSyncDate == nil && input.authorizationGranted != true
        if neverSynced {
            return HealthConnectionStatus(
                kind: .notSetUp,
                headline: "Connect Apple Health",
                explanation: "Your Apple Watch sends data to the Health app on your iPhone. Look After reads from there to show sleep, steps, and recovery.",
                primaryAction: .connect,
                primaryActionLabel: "Connect Apple Health",
                fixSteps: [
                    "Tap Connect Apple Health.",
                    "When iOS asks, allow Sleep, Steps, and Heart Rate.",
                    "Wear your Watch overnight for sleep data."
                ]
            )
        }

        let missing = missingMetrics(from: input)
        let isStale = input.lastSyncDate.map { input.now.timeIntervalSince($0) > input.staleSyncThreshold } ?? false

        if input.hasAnyImportedMetrics && missing.isEmpty && !isStale {
            return HealthConnectionStatus(
                kind: .allGood,
                headline: "Sleep and activity are up to date",
                explanation: "Look After is reading your latest data from the Health app on your iPhone.",
                primaryAction: .none,
                primaryActionLabel: "",
                fixSteps: []
            )
        }

        if input.hasAnyImportedMetrics && isStale {
            return HealthConnectionStatus(
                kind: .syncStale,
                headline: "Health data may be out of date",
                explanation: "Look After hasn't refreshed your sleep and activity recently. Your Watch may have newer data in the Health app.",
                primaryAction: .syncNow,
                primaryActionLabel: "Sync now",
                fixSteps: [
                    "Tap Sync now to pull the latest data from Health.",
                    "Open the Health app to confirm your Watch data is there.",
                    "Keep Bluetooth on so your Watch can sync to your iPhone."
                ],
                missingMetrics: missing
            )
        }

        if input.hasAnyImportedMetrics && !missing.isEmpty {
            return partialStatus(input: input, missing: missing, product: product)
        }

        if input.authorizationGranted == true || input.lastSyncDate != nil {
            return HealthConnectionStatus(
                kind: .waitingForData,
                headline: "Connected, but no data yet",
                explanation: "Look After can read Health, but there isn't sleep or activity data to import yet. Your Watch sends data to the iPhone Health app first.",
                primaryAction: .syncNow,
                primaryActionLabel: "Sync now",
                fixSteps: [
                    "Wear your Apple Watch overnight for sleep.",
                    "Take a short walk to log steps.",
                    "Open the Health app and confirm data appears there.",
                    "Return here and tap Sync now."
                ],
                missingMetrics: ["Sleep", "Steps", "Heart rate"]
            )
        }

        return HealthConnectionStatus(
            kind: .notSetUp,
            headline: "Connect Apple Health",
            explanation: "Your Apple Watch sends data to the Health app on your iPhone. Look After reads from there.",
            primaryAction: .connect,
            primaryActionLabel: "Connect Apple Health",
            fixSteps: ["Tap Connect Apple Health and allow Sleep, Steps, and Heart Rate."]
        )
    }

    private static func missingMetrics(from input: HealthConnectionStatusInput) -> [String] {
        var missing: [String] = []
        if !input.hasSleepData { missing.append("Sleep") }
        if !input.hasActivityData { missing.append("Steps & activity") }
        if !input.hasHeartRateData { missing.append("Heart rate") }
        // HRV is optional recovery signal — missing HRV alone must not block "all good"
        // or keep a Sync now banner that cannot fetch a metric Apple Health does not have.
        return missing
    }

    private static func partialStatus(
        input: HealthConnectionStatusInput,
        missing: [String],
        product: String
    ) -> HealthConnectionStatus {
        let missingList = missing.joined(separator: ", ")
        var fixSteps: [String] = [
            "Open the Health app and confirm the missing data is there.",
            "Tap Sync now in Look After."
        ]

        if missing.contains("Sleep") {
            fixSteps.insert("Wear your Apple Watch overnight with Sleep tracking enabled.", at: 0)
        }
        if missing.contains(where: { $0.contains("Steps") }) {
            fixSteps.insert("Walk with your iPhone or Watch, or enable Steps in Health → Sharing → Apps → \(product).", at: 0)
        }

        return HealthConnectionStatus(
            kind: .partialData,
            headline: "Some health data is missing",
            explanation: "Some data came through, but we couldn't find: \(missingList). Your Watch sends everything to the iPhone Health app first.",
            primaryAction: .syncNow,
            primaryActionLabel: "Sync now",
            fixSteps: fixSteps,
            missingMetrics: missing
        )
    }
}

// MARK: - Deep links

public enum HealthAppLinks {
    public static var healthAppURL: URL? {
        URL(string: "x-apple-health://")
    }
}
