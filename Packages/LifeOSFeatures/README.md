# LifeOSFeatures

**ViewModels and feature orchestration** — no SwiftUI views.

Views live in `Apps/LifeOS-iOS/Views/` and `Apps/LifeOS-iOS/Experience/`.

## Structure

Each feature folder follows:

```
<Feature>/
├── ViewModels/     # @MainActor ObservableObject types
├── Services/       # Feature-specific orchestration (optional)
└── Models/         # Feature-local DTOs only (domain stays in LifeOSCore)
```

## Dependencies

- LifeOSCore (domain)
- LifeOSAI (LLM)
- LifeOSData (persistence)
- ExecutiveBrain (deterministic brain)

## Naming note

`LLMPlanningEngine` handles LLM-assisted day planning conversations. Do not confuse with `ExecutiveBrain.PlanningEngine`, which builds deterministic day plans from world state.
