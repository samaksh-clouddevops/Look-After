# ADR-003: Append-Only Behavior Memory with Separate Analytics

## Status

Accepted — D2.3 refinements, reaffirmed D2.4 (2026-07-31)

## Context

Behavior Memory records task completions, deferrals, and Flow sessions over time. The system will eventually infer patterns (preferred durations, deferral triggers, energy correlations).

Mixing event persistence with analytics in one store creates several risks:

- Retention cleanup could accidentally discard data needed for inference.
- Testing scheduling requires mocking analytics side effects.
- Pattern detection algorithms will change faster than storage schema.

## Decision

**Three-layer separation:**

| Layer | Responsibility |
|-------|----------------|
| `BehaviorMemoryStore` | Append-only event persistence, retention cleanup |
| `BehaviorMemorySnapshotBuilder` | Deterministic aggregation (counts, deferral records) |
| `BehaviorAnalysisEngine` | Pattern detection and learning (future) |

Flow Director consumes `BehaviorMemorySnapshot` from the analysis pipeline, never raw events directly from the store for scheduling decisions.

Retention and archival policies are defined in `BehaviorMemoryRetentionPolicy` (90-day default, 10K event cap, 5 MB limit).

## Consequences

**Positive**

- Store stays a pure event log — easy to audit and migrate.
- Analytics can evolve without storage schema changes (v1 → v2 → v3 migration plan documented).
- Scheduling tests use snapshot fixtures without file I/O.

**Negative**

- Two-step read path (`fetchEvents` → `buildSnapshot`) on every orchestration cycle.
- Pattern inference not yet implemented; snapshots are mostly counts today.

## Alternatives Considered

- **Store computes snapshot on read** — rejected in D2.3; violates single responsibility.
- **Firebase as primary behavior store** — rejected; spec requires on-device, privacy-first storage.
