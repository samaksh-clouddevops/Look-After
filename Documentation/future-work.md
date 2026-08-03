# Future Work

Deferred improvements — not blocking the repository restructure.

## Package extraction

- **LifeOSDesignSystem** as a separate SPM package only if Widget + macOS + iOS need independent release cycles

## Persistence consolidation

Move stores into LifeOSData over time:

- Core: `MedicationStore`, `CycleLogStore`, etc. → `LifeOSData/Repositories/`
- ExecutiveBrain: `DecisionHistoryStore` → `LifeOSData/Storage/`
- LifeOSAI: `KeychainStore` → `LifeOSData/Security/` with `SecretsStoring` protocol in Core

## Dependency injection

- Introduce `Apps/LifeOS-iOS/Composition/AppDependencies.swift` for testable DI
- Wire `AnalyticsEnrichmentProviding` protocol if AI enrichment returns to Data layer

## CI

- GitHub Actions workflow in `Tools/ci/` — xcodebuild + swift test matrix

## Repository hygiene

- Resolve nested git repos (`ADHD/` parent vs `LifeOS/.git`) — single source of truth for contributors
