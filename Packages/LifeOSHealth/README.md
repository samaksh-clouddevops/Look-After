# LifeOSHealth

**HealthKit I/O only** — reads sleep, HRV, heart rate, and workout data.

Platform-specific health sync UI and orchestration lives in `Apps/LifeOS-iOS/Services/HealthSyncService.swift`.

## Files

- `HealthManager.swift` — HealthKit authorization and queries
- `HealthKitObserverService.swift` — background observation
- `HealthFetchProgress.swift` — fetch progress reporting
