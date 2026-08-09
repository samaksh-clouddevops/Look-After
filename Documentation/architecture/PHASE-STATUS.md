# Architecture / infra phase status

**Branch:** `feature/arch-infra-implementation`
**Plan:** [MASTER-IMPLEMENTATION-PLAN.md](./MASTER-IMPLEMENTATION-PLAN.md)
**Updated:** 2026-08-09

| Phase | Status | Notes |
|-------|--------|-------|
| **0 Foundations** | **Done** | Flags, ADRs 005–008, env matrix, inventory, CI, tests |
| **1 Identity + Session** | **Mostly done** | IdentityService (Combine), SessionContainer, bootstrap gate; flag off by default |
| **2 Sync outbox** | **WP 2.1 landed** | Store + worker + task repo enqueue; Firestore transport; flag off by default |
| 3 Brain façade / proxy-only | Not started | Flag + ADR only |
| 4 Split shell / Features | Not started | |
| 5 Event bus | Not started | |
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

1. Phase 2 WP 2.2 — Inbox SQLite local-first
2. Phase 3 — BrainFacade scaffold
3. BG task hook to call `SyncOutboxWorker.drainOnce`

## Test commands

```bash
swift test --package-path Packages/LookAfterCore --filter ArchitectureFeatureFlagsTests
swift test --package-path Packages/LookAfterData --filter IdentityServiceTests
swift test --package-path Packages/LookAfterData --filter SyncOutboxStoreTests
```
