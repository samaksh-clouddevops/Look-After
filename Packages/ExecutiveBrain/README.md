# ExecutiveBrain

**Deterministic executive function engine** — no LLM calls, no SwiftUI.

Pipeline: Signals → World Model → Reasoning → Planner → Decision → Explanation

## Structure

```
Engine/          # ExecutiveBrainEngine, DecisionEngine, PlanningEngine, …
Models/          # BrainState, WorldState, DayPlan, ReasoningTrace
Storage/         # DecisionHistoryStore (persistence — migrate to LookAfterData over time)
```

## Consumers

- `LookAfterFeatures.ContextOrchestrator` — primary integration
- `BrainInspectorView` (debug UI in iOS app)

## Naming note

`PlanningEngine` here builds deterministic day plans. For LLM planning conversations, see `LookAfterFeatures.LLMPlanningEngine`.
