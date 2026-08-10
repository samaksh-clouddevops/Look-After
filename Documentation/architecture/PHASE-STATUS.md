# Architecture / infra phase status

**Branch:** `feature/arch-infra-implementation`
**Plan:** [MASTER-IMPLEMENTATION-PLAN.md](./MASTER-IMPLEMENTATION-PLAN.md)
**Updated:** 2026-08-09

| Phase | Status | Notes |
|-------|--------|-------|
| **0 Foundations** | **Done** | Flags, ADRs, env matrix, inventory, CI |
| **1 Identity + Session** | **Done (flag off)** | Identity Combine, SessionContainer |
| **2 Sync + modules SQLite** | **Done (flag off for outbox)** | Outbox, inbox, health, module entities |
| **3 Brain + proxy AI** | **Done (flag gated)** | Facade + FlowAware; proxy-only surface |
| **4 Bootstrap extract** | **WP 4.1 done** | BootstrapCoordinator (4.2 TasksVM split still open) |
| **5 Event bus** | **Done (flag off)** | SessionEventBus dual-publish |
| **6 Infra hardening** | **Foundation landed** | Proxy request-id logs, App Check stub, rules test plan, metrics route, runbook |
| **7 Brand / multi-account** | **Code dual-path landed** | App Group dual R/W, BG dual IDs, UserStorageRoot — **needs entitlement/plist ops** |
| **8 Polish** | **Foundation landed** | LookAfterAppGroup pkg, export/encrypt, outbox debugStatus — flag soak remaining |

## Ops docs

- [infra-ops-runbook.md](./infra-ops-runbook.md)
- [firestore-rules-test-plan.md](./firestore-rules-test-plan.md)
- [environment-matrix.md](./environment-matrix.md)

## Still requires human / platform work

1. Add `group.com.lookafter` to app + widget entitlements
2. Dual BG identifiers in Info.plist `BGTaskSchedulerPermittedIdentifiers`
3. Firebase App Check SDK + real token provider
4. Staging proxy deploy + `APP_CHECK_ENFORCE` soak
5. Default architecture flags **on** after 1–2 TestFlight builds
6. Phase 4.2 TasksViewModel split (large, optional next)

## How to enable (dev)

```swift
ArchitectureFeatureFlags.useSessionContainer = true
ArchitectureFeatureFlags.useSyncOutbox = true
ArchitectureFeatureFlags.useBrainFacade = true
ArchitectureFeatureFlags.useTypedEventBus = true
```

## Test commands

```bash
swift test --package-path Packages/LookAfterCore --filter ArchitectureFeatureFlagsTests
swift test --package-path Packages/LookAfterCore --filter BrainFacadeTests
swift test --package-path Packages/LookAfterCore --filter SessionEventBusTests
swift test --package-path Packages/LookAfterData --filter IdentityServiceTests
swift test --package-path Packages/LookAfterData --filter SyncOutboxStoreTests
swift test --package-path Packages/LookAfterData --filter InboxSQLiteStoreTests
swift test --package-path Packages/LookAfterData --filter HealthSummarySQLiteStoreTests
swift test --package-path Packages/LookAfterData --filter JSONEntitySQLiteStoreTests
```
