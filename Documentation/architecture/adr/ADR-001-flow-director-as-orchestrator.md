# ADR-001: FlowDirector as Orchestrator, Not Decision Engine

## Status

Accepted — D2.4 (2026-07-31)

## Context

FlowOS needs a component that runs proactively, fuses signals from health, calendar, behavior, and device state, and publishes a `FlowSurface` for the Flow Canvas and widgets.

Two designs were possible:

1. **Monolithic director** — one class that reads signals, applies rules, generates copy, and builds UI models.
2. **Orchestrator + engines** — a thin coordinator that delegates scheduling, confidence, briefing, and surface assembly to dedicated components.

The product spec states: *"Flow Director owns all decisions"* but also *"AI does not choose tasks—it explains Flow Director's choices."* Scheduling must be testable without LLM, persistence, or UI.

## Decision

`FlowDirector` is an **orchestrator only**. It wires dependencies in a fixed pipeline and publishes `FlowSurface`. It contains almost no business logic.

Pipeline:

```
EnvironmentContextProvider
  → BehaviorAnalysisEngine
  → FlowSchedulingEngine
  → FlowConfidenceEngine
  → FlowBriefingProvider (ExecutiveBrain / LLM in D2.5)
  → FlowSurfaceBuilder
  → publish FlowSurface
```

Scheduling decisions live in `FlowSchedulingEngine` and composable rules. Confidence lives in `FlowConfidenceEngine`. Surface assembly lives in `FlowSurfaceBuilder`.

## Consequences

**Positive**

- Each stage is unit-testable in isolation.
- LLM can be swapped or disabled without touching scheduling logic.
- FlowDirector stays small as rules and signals grow.

**Negative**

- More types and dependency injection wiring at the app composition root.
- Orchestration order must be documented and kept stable.

## Alternatives Considered

- **ExecutiveBrain evolution in place** — rejected; mixes LLM calls with scheduling and is not deterministic.
- **Single `schedule()` method on FlowDirector** — rejected; would grow into an unmaintainable god method.
