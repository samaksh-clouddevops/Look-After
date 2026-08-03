# LifeOS Packages

All folders here are **Swift packages** (each has a `Package.swift`). They are **not** standalone Xcode apps.

## One workspace rule

Open **only** the main project:

```bash
cd /path/to/LifeOS
xcodegen generate
open LookAfter.xcodeproj
```

Or use `LifeOS.code-workspace`.

## Dependency graph

```mermaid
flowchart BT
    Core[LookAfterCore]
    AI[LookAfterAI]
    Data[LookAfterData]
    Health[LookAfterHealth]
    EB[ExecutiveBrain]
    Features[LookAfterFeatures]

    Core --> AI
    Core --> Data
    Core --> Health
    Core --> EB
    Core --> Features
    AI --> Features
    Data --> Features
    EB --> Features
```

**Rules:** No circular dependencies. `LookAfterCore` is the foundation. `LookAfterFeatures` is the top integration layer for ViewModels.

## Package responsibilities

| Package | Responsibility | Put new code here when… |
|---------|----------------|-------------------------|
| **LookAfterCore** | Domain models, scheduling, semantics, design system, pure logic | It has no I/O and no UI beyond shared design tokens/components |
| **ExecutiveBrain** | Deterministic decision engine (WorldState, Planning, Decision) | It's rule-based brain logic without LLM calls |
| **LookAfterAI** | GLM provider, FlowDirector, prompts, semantic analysis | It calls an LLM or wraps AI inference |
| **LookAfterData** | Persistence, Firebase, repositories, environment signals | It reads/writes storage or syncs to cloud |
| **LookAfterHealth** | HealthKit I/O | It touches HealthKit APIs |
| **LookAfterFeatures** | ViewModels and feature orchestration | It's presentation state for SwiftUI views |

## Internal folder conventions

Each package uses consistent subfolders where applicable:

- `Models/` — Codable domain types
- `Protocols/` — interfaces for DI
- `Repositories/` / `Persistence/` / `Storage/` — I/O (LookAfterData)
- `DesignSystem/` — UI tokens and shared components (LookAfterCore)
- `ViewModels/` — `@MainActor` presentation logic (LookAfterFeatures)
- `Engine/` — deterministic engines (ExecutiveBrain)
- `GLM/` — LLM service and configuration (LookAfterAI)

## Where to put new code

```
SwiftUI view (rendering only)     → Apps/LookAfter-iOS/Views/
ViewModel                           → LookAfterFeatures/<Feature>/ViewModels/
Platform adapter (HealthKit, etc.)  → Apps/LookAfter-iOS/Services/ or LookAfterHealth
Domain model                        → LookAfterCore/Models/
Repository / persistence            → LookAfterData/
LLM prompt or AI call               → LookAfterAI/
Deterministic brain logic           → ExecutiveBrain/
Design token / shared component     → LookAfterCore/DesignSystem/
```

## Command-line tests

```bash
cd Packages/LookAfterCore && swift test
cd Packages/ExecutiveBrain && swift test
cd Packages/LookAfterData && swift test
cd Packages/LookAfterFeatures && swift test
```

## Architecture decisions

See [Documentation/architecture/adr/](../Documentation/architecture/adr/).
