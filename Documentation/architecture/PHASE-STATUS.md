# Architecture / infra phase status

**Branch:** `feature/arch-infra-implementation`  
**Plan:** [MASTER-IMPLEMENTATION-PLAN.md](./MASTER-IMPLEMENTATION-PLAN.md)  
**Updated:** 2026-08-09

| Phase | Status | Notes |
|-------|--------|-------|
| **0 Foundations** | **In progress / mostly done** | Flags, ADRs 005–008, env matrix, singleton inventory, CI notes, unit tests |
| **1 Identity + Session** | **Started** | `IdentityService`, `SessionContainer`, bootstrap generation gate (flag off by default) |
| 2 Sync outbox | Not started | |
| 3 Brain façade / proxy-only | Not started | Flag + ADR only |
| 4 Split shell / Features | Not started | |
| 5 Event bus | Not started | |
| 6 Infra hardening | Not started | |
| 7 Brand / multi-account | Not started | |
| 8 Polish | Not started | |

## Landed on this branch

| Artifact | Path |
|----------|------|
| Feature flags | `Packages/LookAfterCore/.../Config/ArchitectureFeatureFlags.swift` |
| Flag tests | `Packages/LookAfterCore/Tests/.../ArchitectureFeatureFlagsTests.swift` |
| Identity | `Packages/LookAfterData/.../Identity/IdentityService.swift` |
| Session | `Packages/LookAfterData/.../Session/SessionContainer.swift` |
| Identity tests | `Packages/LookAfterData/Tests/.../IdentityServiceTests.swift` |
| Bootstrap gate | `Apps/.../AppShellState.swift` |
| ADRs | `adr/ADR-005` … `ADR-008` |
| Env matrix | `environment-matrix.md` |
| Singleton inventory | `singleton-inventory.md` |

## How to enable Session path (dev)

```swift
ArchitectureFeatureFlags.useSessionContainer = true
```

Default remains **false** (legacy bootstrap) until soak.

## Next PR targets

1. Finish Phase 0: link plan from `Documentation/future-work.md` / architecture README if present  
2. Phase 1 soak: optional Combine bridge Identity ← FirebaseManager (replace 500ms poll)  
3. Phase 2 WP 2.1: `sync_outbox` table + OutboxWorker  

## Test commands

```bash
swift test --package-path Packages/LookAfterCore --filter ArchitectureFeatureFlagsTests
swift test --package-path Packages/LookAfterData --filter IdentityServiceTests
```
