# Singleton inventory

**Phase 0 WP 0.6** — baseline for SessionContainer migration.

| Type (file) | Path | Area |
|-------------|------|------|
| `BackgroundAnalyticsScheduler` | `Apps/LookAfter-iOS/Services/BackgroundAnalyticsScheduler.swift` | App |
| `ActivityStateController` | `Apps/LookAfter-iOS/Services/Execution/ActivityStateController.swift` | App |
| `ExecutionEnvironmentCoordinator` | `Apps/LookAfter-iOS/Services/Execution/ExecutionEnvironmentCoordinator.swift` | App |
| `ExecutionFocusCoordinator` | `Apps/LookAfter-iOS/Services/Execution/ExecutionFocusCoordinator.swift` | App |
| `LookAfterFocusIntent` | `Apps/LookAfter-iOS/Services/Execution/LookAfterFocusIntent.swift` | App |
| `HealthSyncService` | `Apps/LookAfter-iOS/Services/HealthSyncService.swift` | App |
| `LiveActivityManager` | `Apps/LookAfter-iOS/Services/LiveActivityManager.swift` | App |
| `NotificationCoordinator` | `Apps/LookAfter-iOS/Services/NotificationCoordinator.swift` | App |
| `NotificationPermissionService` | `Apps/LookAfter-iOS/Services/NotificationPermissionService.swift` | App |
| `NotificationRouter` | `Apps/LookAfter-iOS/Services/NotificationRouter.swift` | App |
| `NotificationScheduler` | `Apps/LookAfter-iOS/Services/NotificationScheduler.swift` | App |
| `LookAfterIntentBridge` | `Apps/LookAfter-iOS/Services/Shortcuts/LookAfterIntentBridge.swift` | App |
| `WidgetSyncService` | `Apps/LookAfter-iOS/Services/WidgetSyncService.swift` | App |
| `DecisionHistoryStore` | `Packages/ExecutiveBrain/Sources/ExecutiveBrain/Storage/DecisionHistoryStore.swift` | ExecutiveBrain |
| `ChiefOfStaffBriefingSynthesizer` | `Packages/LookAfterAI/Sources/LookAfterAI/Briefing/ChiefOfStaffBriefingSynthesizer.swift` | LookAfterAI |
| `GLMConfigurationStore` | `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Configuration/GLMConfigurationStore.swift` | LookAfterAI |
| `GLMUsageLogger` | `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Logging/GLMUsageLogger.swift` | LookAfterAI |
| `GLMKeyManager` | `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Providers/GLMKeyManager.swift` | LookAfterAI |
| `GLMService` | `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Service/GLMService.swift` | LookAfterAI |
| `InteractionTelemetryLogger` | `Packages/LookAfterCore/Sources/LookAfterCore/Behavior/InteractionTelemetryLogger.swift` | LookAfterCore |
| `CascadeDistiller` | `Packages/LookAfterCore/Sources/LookAfterCore/Briefing/CascadeDistiller.swift` | LookAfterCore |
| `CaptureGraphStore` | `Packages/LookAfterCore/Sources/LookAfterCore/Capture/CaptureGraphStore.swift` | LookAfterCore |
| `ResumeEngine` | `Packages/LookAfterCore/Sources/LookAfterCore/Context/ResumeEngine.swift` | LookAfterCore |
| `GapAuction` | `Packages/LookAfterCore/Sources/LookAfterCore/Planning/GapAuction.swift` | LookAfterCore |
| `HighLoadDayTracker` | `Packages/LookAfterCore/Sources/LookAfterCore/Planning/HighLoadDayTracker.swift` | LookAfterCore |
| `ParkedTaskQueue` | `Packages/LookAfterCore/Sources/LookAfterCore/Planning/ParkedTaskQueue.swift` | LookAfterCore |
| `SomedayVault` | `Packages/LookAfterCore/Sources/LookAfterCore/Planning/SomedayVault.swift` | LookAfterCore |
| `LifeEngine` | `Packages/LookAfterCore/Sources/LookAfterCore/Review/LifeEngine.swift` | LookAfterCore |
| `InteractionEngine` | `Packages/LookAfterCore/Sources/LookAfterCore/Utilities/InteractionEngine.swift` | LookAfterCore |
| `InteractionTelemetry` | `Packages/LookAfterCore/Sources/LookAfterCore/Utilities/InteractionTelemetry.swift` | LookAfterCore |
| `AnalyticsCacheManager` | `Packages/LookAfterData/Sources/LookAfterData/Analytics/AnalyticsCacheManager.swift` | LookAfterData |
| `BackgroundAnalyticsService` | `Packages/LookAfterData/Sources/LookAfterData/Analytics/BackgroundAnalyticsService.swift` | LookAfterData |
| `BehavioralVaultStore` | `Packages/LookAfterData/Sources/LookAfterData/Behavior/BehavioralVaultStore.swift` | LookAfterData |
| `FirebaseManager` | `Packages/LookAfterData/Sources/LookAfterData/Firebase/FirebaseManager.swift` | LookAfterData |
| `FirebaseMessagingService` | `Packages/LookAfterData/Sources/LookAfterData/Firebase/FirebaseMessagingService.swift` | LookAfterData |
| `AccountIdentity` | `Packages/LookAfterData/Sources/LookAfterData/Identity/AccountIdentity.swift` | LookAfterData |
| `LicenseManager` | `Packages/LookAfterData/Sources/LookAfterData/License/LicenseManager.swift` | LookAfterData |
| `LocalPersistenceManager` | `Packages/LookAfterData/Sources/LookAfterData/Persistence/LocalPersistenceManager.swift` | LookAfterData |
| `TaskSQLiteStore` | `Packages/LookAfterData/Sources/LookAfterData/Persistence/TaskSQLiteStore.swift` | LookAfterData |
| `TaskStore` | `Packages/LookAfterData/Sources/LookAfterData/Stores/TaskStore.swift` | LookAfterData |
| `ParkedTaskRecoveryService` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Behavior/ParkedTaskRecoveryService.swift` | LookAfterFeatures |
| `TelemetrySynthesizerService` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Behavior/TelemetrySynthesizerService.swift` | LookAfterFeatures |
| `CalendarBaselineAnalyzer` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Calendar/CalendarBaselineAnalyzer.swift` | LookAfterFeatures |
| `CaptureOfflineQueue` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Capture/CaptureOfflineQueue.swift` | LookAfterFeatures |
| `CaptureRouter` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Capture/CaptureRouter.swift` | LookAfterFeatures |
| `FactoryResetManager` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/FactoryReset/FactoryResetManager.swift` | LookAfterFeatures |
| `HealthStore` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Health/HealthStore.swift` | LookAfterFeatures |
| `DeferralRecoveryCoordinator` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Planning/Recovery/DeferralRecoveryCoordinator.swift` | LookAfterFeatures |
| `TimelineService` | `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Timeline/TimelineService.swift` | LookAfterFeatures |
| `HealthKitObserverService` | `Packages/LookAfterHealth/Sources/LookAfterHealth/HealthKitObserverService.swift` | LookAfterHealth |
| `EmailTriageService` | `Packages/LookAfterIntegrations/Sources/LookAfterIntegrations/Email/EmailTriageService.swift` | LookAfterIntegrations |
| `EmailTriageService` | `Packages/LookAfterIntegrations/Sources/LookAfterIntegrations/Email/EmailTriageService.swift` | LookAfterIntegrations |

Total: **52** `shared` sites.

Migrate user-scoped services into SessionContainer (Phase 1). Keep process-wide: Keychain, BG tasks, Firebase configure.
