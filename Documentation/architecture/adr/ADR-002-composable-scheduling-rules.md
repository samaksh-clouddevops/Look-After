# ADR-002: Composable Scheduling Rules

## Status

Accepted — D2.4 (2026-07-31)

## Context

ATTENTION_OS_SPEC defines multiple orchestration rules (meeting soon, low energy, deferral patterns, calendar gaps, battery, deep-work windows). These rules interact — e.g., an in-progress task should continue even when a meeting is approaching, but duration should still be capped.

A single large `schedule()` method would become difficult to test, reason about, and extend.

## Decision

Scheduling logic is implemented as **independently testable rule objects** conforming to `FlowSchedulingRuleProtocol`. `FlowSchedulingEngine` composes rules in a fixed pipeline order:

1. `ContinueTaskRule`
2. `MeetingSoonRule`
3. `LowEnergyRule`
4. `DeepWorkWindowRule`
5. `DeferralRule`
6. `BatteryRule`
7. `CalendarGapRule`

Each rule mutates a shared `MutableSchedulingState`. Rules are deterministic: identical `FlowDirectorInput` always produces identical output.

## Consequences

**Positive**

- Every rule has dedicated unit tests.
- New rules (e.g., rain + no meetings) can be added without modifying existing rules.
- Rule matrix documents behavior for product and engineering review.

**Negative**

- Rule order matters and must be maintained consciously.
- Shared mutable state requires discipline to avoid rule coupling.

## Alternatives Considered

- **Priority score aggregation** — rejected for D2.4; harder to explain and debug than explicit rule pipeline.
- **Hard-coded switch on environment** — rejected; does not scale with spec rule count.
