# Package Guide

## Decision tree

```
Is it a SwiftUI view?
  └─ Yes → Apps/LifeOS-iOS/Views/ or Experience/
  └─ No ↓

Is it @MainActor presentation state?
  └─ Yes → LifeOSFeatures/<Feature>/ViewModels/
  └─ No ↓

Does it call an LLM?
  └─ Yes → LifeOSAI/
  └─ No ↓

Does it read/write disk or Firebase?
  └─ Yes → LifeOSData/
  └─ No ↓

Does it use HealthKit?
  └─ Yes → LifeOSHealth/ (or app Services/ for sync orchestration)
  └─ No ↓

Is it deterministic brain logic (no LLM)?
  └─ Yes → ExecutiveBrain/
  └─ No ↓

Is it a shared model, protocol, or design token?
  └─ Yes → LifeOSCore/
```

## App target rules

| Folder | Contents |
|--------|----------|
| `App/` | Entry point (`LifeOSApp.swift`, `ContentView.swift`) |
| `Composition/` | Dependency wiring (future: `AppDependencies.swift`) |
| `Experience/` | App shell, AI Executive mode |
| `Views/` | SwiftUI only — rendering and bindings |
| `Services/` | Platform adapters (HealthKit sync, Speech, LiveActivity, Widget) |
| `Resources/` | Bundled assets, example profiles |

## macOS

macOS shares a subset of iOS views via `project.yml`. See [architecture/macOS-shared-views.md](architecture/macOS-shared-views.md).

## Tests

- Package tests: colocated under `Packages/<Name>/Tests/`
- Aggregated app tests: `LifeOSTests` target in `project.yml`
