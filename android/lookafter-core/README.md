# lookafter-core (Phase 1 — Physics Port)

Pure Kotlin/JVM module. **Zero** `android.*` dependencies.

Ports the iOS `LookAfterCore` scheduling physics + UDF engine:

| Component | Package | iOS source |
|---|---|---|
| Domain models | `com.lookafter.core.models` | `LifeTask`, `TimeConstraint`, ephemerality enums |
| `TaskReaper` | `com.lookafter.core.scheduling` | `TaskEphemerality.swift` |
| `DayScheduleReconciler` | `com.lookafter.core.planning` | `DayScheduleReconciler.swift` |
| `ConflictResolutionCascade` | `com.lookafter.core.planning` | `ConflictResolutionCascade.swift` |
| `WeeklyReviewAggregator` | `com.lookafter.core.planning` | Phase-1 Android addition |
| `LifeState` / `LookAfterIntent` / `LifeEngine` | `com.lookafter.core.engine` | Phase-2 UDF dispatcher (`StateFlow`) |

## Build / test

From `android/`:

```bash
./gradlew :lookafter-core:test
```

Requires JDK 17+.

## Immutability contract

- All domain types are `data class` / `enum class` / `sealed class`
- Engines are `object` pure functions
- Mutations return `copy(...)` — never in-place edits
