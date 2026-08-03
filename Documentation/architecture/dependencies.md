# Package Dependencies

## Graph

```mermaid
flowchart BT
    Core[LookAfterCore]
    AI[LookAfterAI]
    Data[LookAfterData]
    Health[LookAfterHealth]
    EB[ExecutiveBrain]
    Features[LookAfterFeatures]
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

1. **LookAfterCore** — no dependencies on other LifeOS packages
2. **LookAfterAI, LookAfterData, LookAfterHealth, ExecutiveBrain** — depend on Core only (Data also depends on AI for test targets)
3. **LookAfterFeatures** — integrates Core, AI, Data, ExecutiveBrain
4. **Apps** — depend on Features, Core, Health, and platform frameworks

## Decoupling notes

- `CognitiveModel` lives in **LookAfterCore** so LookAfterData analytics does not import LookAfterAI
- `LLMPlanningEngine` (Features) is distinct from `PlanningEngine` (ExecutiveBrain)
- Persistence consolidation (Core/EB stores → LookAfterData) is documented in [future-work.md](../future-work.md)

## ADRs

Historical decisions: [adr/](adr/)
