# Architecture / infra phase status

**Branch:** `feature/arch-infra-implementation`
**Plan:** [MASTER-IMPLEMENTATION-PLAN.md](./MASTER-IMPLEMENTATION-PLAN.md)
**Updated:** 2026-08-09

| Phase | Status | Notes |
|-------|--------|-------|
| **0 Foundations** | **Done** | Flags, ADRs 005–008, env matrix, inventory, CI, tests |
| **1 Identity + Session** | **Done (flag off)** | Identity Combine, SessionContainer + brain/inbox/outbox refs |
| **2 Sync + modules SQLite** | **WP 2.1–2.4 landed** | Outbox, inbox, health, bills/shopping/relationships/journal |
| **3 Brain + proxy AI** | **Done (flag gated)** | Facade + FlowAware adapter; proxy-only surface |
| **4 Bootstrap extract** | **WP 4.1 landed** | `BootstrapCoordinator` + `BootstrapExecuting` |
| **5 Event bus** | **Landed (flag off)** | `SessionEventBus` dual-publish when `useTypedEventBus` |
| 6 Infra hardening | Not started | |
| 7 Brand / multi-account | Not started | |
| 8 Polish | Not started | |

## Landed on this branch

| Artifact | Path |
|----------|------|
| Feature flags | `ArchitectureFeatureFlags.swift` |
| Identity + Combine | `IdentityService.swift` |
| Session | `SessionContainer.swift` |
| Outbox store/worker | `Sync/SyncOutbox*.swift` |
| Task cloud path | `Repositories.swift` → outbox when flag on |
| Bootstrap drain | `AppShellState.runBootstrapWork` |
| Tests | `ArchitectureFeatureFlagsTests`, `IdentityServiceTests`, `SyncOutboxStoreTests` |
| ADRs / env / inventory | `Documentation/architecture/` |

## How to enable (dev)

```swift
ArchitectureFeatureFlags.useSessionContainer = true
ArchitectureFeatureFlags.useSyncOutbox = true
```

Defaults remain **false** until soak.

## Next work packages

1. Phase 4.2 — Split TasksViewModel into services
2. Phase 6 — App Check + outbox metrics Settings row
3. Default flags on after soak; delete legacy Notification path

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
