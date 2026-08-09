# ADR-005: Session composition root

**Status:** Proposed  
**Date:** 2026-08-09  
**Plan:** [MASTER-IMPLEMENTATION-PLAN.md](../MASTER-IMPLEMENTATION-PLAN.md) Phase 1  

## Context

`AppShellState` constructs and owns most services via `.shared` singletons. That couples UI, bootstrap, capture, brain, and sync; hurts tests; and makes sign-out / multi-account teardown unsafe.

## Decision

Introduce a **`SessionContainer`** (composition root) created after identity is stable:

- Owns user-scoped services: task store/repos, brain façade, health gateway, outbox, event bus.
- Constructed by factory `SessionContainer.make(environment:flags:)`.
- `AppShellState` becomes a thin holder of the session + navigation UI state.
- Gated by `ArchitectureFeatureFlags.useSessionContainer` until default-on.

Process-wide only: Keychain façade, BG task registration, Firebase app configure.

## Consequences

- Features receive dependencies via init, not `.shared`.
- Sign-out / factory reset call `session.tearDown()`.
- Migration is dual-path until flag soaks.

## Alternatives considered

- Service locator only — rejected (still global mutable).
- Full TCA rewrite — deferred (high cost).
