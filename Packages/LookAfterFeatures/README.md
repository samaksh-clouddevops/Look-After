# LookAfterFeatures

**ViewModels and feature orchestration** — no SwiftUI views.

Views live in `Apps/LookAfter-iOS/Views/` and `Apps/LookAfter-iOS/Experience/`.

## Structure

Each feature folder follows:

```
<Feature>/
├── ViewModels/     # @MainActor ObservableObject types
├── Services/       # Feature-specific orchestration (optional)
└── Models/         # Feature-local DTOs only (domain stays in LookAfterCore)
```

## Dependencies

- LookAfterCore (domain)
- LookAfterAI (LLM)
- LookAfterData (persistence)
- ExecutiveBrain (deterministic brain)

## Naming note

`LLMPlanningEngine` handles LLM-assisted day planning conversations. Do not confuse with `ExecutiveBrain.PlanningEngine`, which builds deterministic day plans from world state.
