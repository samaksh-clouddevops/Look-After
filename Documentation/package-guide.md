# Package Guide

## Decision tree

```
Is it a SwiftUI view?
  └─ Yes → Apps/LookAfter-iOS/Views/ or Experience/
  └─ No ↓

Is it @MainActor presentation state?
  └─ Yes → LookAfterFeatures/<Feature>/ViewModels/
  └─ No ↓

Does it call an LLM?
  └─ Yes → LookAfterAI/
  └─ No ↓

Does it read/write disk or Firebase?
  └─ Yes → LookAfterData/
  └─ No ↓

Does it use HealthKit?
  └─ Yes → LookAfterHealth/ (or app Services/ for sync orchestration)
  └─ No ↓

Is it deterministic brain logic (no LLM)?
  └─ Yes → ExecutiveBrain/
  └─ No ↓

Is it a shared model, protocol, or design token?
  └─ Yes → LookAfterCore/
```

## App target rules

| Folder | Contents |
|--------|----------|
| `App/` | Entry point (`LookAfterApp.swift`, `ContentView.swift`) |
| `Composition/` | Dependency wiring (future: `AppDependencies.swift`) |
| `Experience/` | App shell, AI Executive mode |
| `Views/` | SwiftUI only — rendering and bindings |
| `Services/` | Platform adapters (HealthKit sync, Speech, LiveActivity, Widget) |
| `Resources/` | Bundled assets, example profiles |

## macOS

macOS shares a subset of iOS views via `project.yml`. See [architecture/macOS-shared-views.md](architecture/macOS-shared-views.md).

## Tests

- Package tests: colocated under `Packages/<Name>/Tests/`
- Aggregated app tests: `LookAfterTests` target in `project.yml`
