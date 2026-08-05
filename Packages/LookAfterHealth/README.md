# LookAfterHealth

**HealthKit I/O only** — reads sleep, HRV, heart rate, and workout data.

Platform-specific health sync UI and orchestration lives in `Apps/LookAfter-iOS/Services/HealthSyncService.swift`.

## Files

- `HealthManager.swift` — HealthKit authorization and queries (sleep + workouts are separate code paths)
- `SleepNightAggregator.swift` — deduplicates sleep across iPhone Sleep, Apple Watch, and sleep trackers
- `HealthSourceCatalog.swift` — known workout-only apps (Motra) excluded from sleep aggregation
- `HealthKitObserverService.swift` — background observation
- `HealthFetchProgress.swift` — fetch progress reporting

## Sleep architecture

HealthKit stores **overlapping sleep samples** from iPhone Sleep, Apple Watch, and dedicated sleep trackers (AutoSleep, Pillow, etc.). Summing sample durations inflates totals (e.g. 7h actual → 11.6h displayed).

**Workout apps are separate:** Motra (`com.trainfitness.ios`) and similar apps write `HKWorkout` samples only — read by `fetchWorkoutData()`, never mixed into sleep. `HealthSourceCatalog` documents workout-only writers as a defensive filter on sleep samples.

`SleepNightAggregator` unions asleep intervals, selects the primary last-night session, and takes stage breakdown from the best sleep source (Apple Watch preferred).
