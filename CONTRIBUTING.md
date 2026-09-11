# Contributing to LifeOS

Thank you for contributing. This project follows a strict modular architecture — please read before opening a PR.

## Setup

See [Documentation/getting-started.md](Documentation/getting-started.md).

## Where to put code

See [Documentation/package-guide.md](Documentation/package-guide.md) and [Packages/README.md](Packages/README.md).

Quick rules:

| Layer | Location |
|-------|----------|
| SwiftUI views | `Apps/LookAfter-iOS/Views/` |
| ViewModels | `LookAfterFeatures/<Feature>/ViewModels/` |
| Domain models | `LookAfterCore/` |
| Persistence | `LookAfterData/` |
| LLM / AI | `LookAfterAI/` |
| HealthKit | `LookAfterHealth/` |
| Deterministic brain | `ExecutiveBrain/` |
| Platform adapters | `Apps/LookAfter-iOS/Services/` |

## Pull request checklist

1. Run `xcodegen generate` if you changed `project.yml` or moved top-level folders
2. iOS build passes: `xcodebuild -scheme LookAfter-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build`
3. macOS build passes: `xcodebuild -scheme LookAfter-macOS -destination 'platform=macOS' build`
4. Relevant package tests pass: `cd Packages/<Name> && swift test`
5. No new circular package dependencies
6. No secrets committed (`.env`, `GoogleService-Info.plist`)

## Code style

- 4-space indentation for Swift (see `.editorconfig`)
- Match existing naming and folder conventions in the package you edit
- Views: rendering and bindings only — business logic belongs in ViewModels or domain packages

## Architecture decisions

Significant structural changes should include an ADR in `Documentation/architecture/adr/`.

## Questions

Open an issue or refer to [Documentation/README.md](Documentation/README.md).
