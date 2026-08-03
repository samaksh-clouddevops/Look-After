# Package Dependencies

## Graph

```mermaid
flowchart BT
    Core[LifeOSCore]
    AI[LifeOSAI]
    Data[LifeOSData]
    Health[LifeOSHealth]
    EB[ExecutiveBrain]
    Features[LifeOSFeatures]
    Apps[Apps targets]

    Core --> AI
    Core --> Data
    Core --> Health
    Core --> EB
    AI --> Data
    Core --> Features
    AI --> Features
    Data --> Features
    EB --> Features
    Health --> Apps
    Features --> Apps
    Core --> Apps
```

## Layering rules

1. **LifeOSCore** — no dependencies on other LifeOS packages
2. **LifeOSAI, LifeOSData, LifeOSHealth, ExecutiveBrain** — depend on Core only (Data also depends on AI for test targets)
3. **LifeOSFeatures** — integrates Core, AI, Data, ExecutiveBrain
4. **Apps** — depend on Features, Core, Health, and platform frameworks

## Decoupling notes

- `CognitiveModel` lives in **LifeOSCore** so LifeOSData analytics does not import LifeOSAI
- `LLMPlanningEngine` (Features) is distinct from `PlanningEngine` (ExecutiveBrain)
- Persistence consolidation (Core/EB stores → LifeOSData) is documented in [future-work.md](../future-work.md)

## ADRs

Historical decisions: [adr/](adr/)
