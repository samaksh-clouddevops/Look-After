# Look After

**Look After** is an AI-powered executive function operating system for Apple platforms (iOS, macOS, Widget).

> **Current release:** [0.1.0-alpha](Documentation/releases/0.1.0-alpha.md) — first alpha (August 2026).  
> Install from source; TestFlight coming after PR merge to `main`.

## Quick start

```bash
xcodegen generate
open LookAfter.xcodeproj
```

See [Documentation/getting-started.md](Documentation/getting-started.md) for prerequisites, Firebase setup, and signing.

## Repository layout

```
LifeOS/
├── Apps/           # iOS, macOS, Widget targets
├── Config/         # Entitlements, Firebase plist (local), signing template
├── Documentation/  # Architecture docs, ADRs, guides
├── Packages/       # Six Swift packages (Core, AI, Data, Features, Health, ExecutiveBrain)
├── Scripts/        # Developer scripts
└── project.yml     # XcodeGen spec
```

## Documentation

| Guide | Link |
|-------|------|
| Architecture index | [Documentation/README.md](Documentation/README.md) |
| Package overview | [Packages/README.md](Packages/README.md) |
| Build & test | [Documentation/build-and-test.md](Documentation/build-and-test.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |

## Features

- **Executive Brain** — deterministic decision engine with energy-aware scheduling
- **AI Coach** — LLM-powered conversational support (GLM provider)
- **Universal Inbox** — capture and categorize across life areas
- **ADHD scaffolding** — emergency mode, focus sessions, task decomposition
- **HealthKit integration** — sleep, HRV, heart rate (privacy-first, on-device)
- **macOS productivity monitor** — cross-device context via Firebase

## License

MIT — see [LICENSE](LICENSE).
