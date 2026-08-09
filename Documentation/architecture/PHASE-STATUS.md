# Architecture / infra phase status

**Branch:** `feature/arch-infra-implementation`
**Plan:** [MASTER-IMPLEMENTATION-PLAN.md](./MASTER-IMPLEMENTATION-PLAN.md)
**Updated:** 2026-08-09

| Phase | Status | Notes |
|-------|--------|-------|
| **0 Foundations** | **Done** | Flags, ADRs 005–008, env matrix, inventory, CI, tests |
| **1 Identity + Session** | **Done (flag off)** | Identity Combine, SessionContainer + brain/inbox/outbox refs |
| **2 Sync outbox + inbox** | **WP 2.1–2.2 landed** | Outbox + Inbox SQLite local-first + BG drain hook |
| **3 Brain façade** | **Scaffold landed** | `BrainFacade` + deterministic backend; proxy-only still ADR/flag only |
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

1. Phase 2 WP 2.3 — Health summaries SQLite
2. Wire BrainViewModel to BrainFacade behind `useBrainFacade`
3. Phase 3.2 — enforce `proxyOnlyAI` in `GLMService`
4. Phase 4.1 — extract `BootstrapCoordinator` from AppShellState

## Test commands

```bash
swift test --package-path Packages/LookAfterCore --filter ArchitectureFeatureFlagsTests
swift test --package-path Packages/LookAfterCore --filter BrainFacadeTests
swift test --package-path Packages/LookAfterData --filter IdentityServiceTests
swift test --package-path Packages/LookAfterData --filter SyncOutboxStoreTests
swift test --package-path Packages/LookAfterData --filter InboxSQLiteStoreTests
```
