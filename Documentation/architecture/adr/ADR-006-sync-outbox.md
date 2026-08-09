# ADR-006: Sync outbox for cloud mutations

**Status:** Proposed  
**Date:** 2026-08-09  
**Plan:** Phase 2 WP 2.1  

## Context

Firestore writes are often fire-and-forget (`try?` / detached Task). Offline or flaky network drops mutations even when local SQLite succeeded.

## Decision

Local SQLite is **authoritative**. Cloud writes enqueue into a `sync_outbox` table and are drained by an `OutboxWorker` with backoff, network monitoring, and BG task hooks.

- Ops: create / update / delete  
- Idempotent keys: entity_type + entity_id + op revision  
- Flag: `ArchitectureFeatureFlags.useSyncOutbox`

## Consequences

- Reliable offline→online convergence  
- Need quarantine UI for poison messages  
- Slightly delayed cloud visibility (acceptable)

## Alternatives considered

- Firestore offline persistence only — insufficient for ordered multi-entity ops and custom merge.
- Always block UI on cloud — poor UX offline.
