# Future Work

Deferred improvements — not blocking the repository restructure.

## Master architecture & infrastructure plan

**Active implementation:** branch `feature/arch-infra-implementation`
**Ordered plan:** [architecture/MASTER-IMPLEMENTATION-PLAN.md](architecture/MASTER-IMPLEMENTATION-PLAN.md)
**Phase status:** [architecture/PHASE-STATUS.md](architecture/PHASE-STATUS.md)

## Apple Design Award craft program

**Roadmap:** [releases/APPLE-DESIGN-AWARD-ROADMAP.md](releases/APPLE-DESIGN-AWARD-ROADMAP.md) — 24-week Inclusivity/Interaction polish plan (award-worthiness, not a guarantee).

## UX excellence (do this first)

**Roadmap:** [releases/UX-EXCELLENCE-ROADMAP.md](releases/UX-EXCELLENCE-ROADMAP.md) — 12-week path to top-notch daily UX on the core loop (hero → focus → capture). Awards packaging comes after this bar.

## Package extraction

- **LifeOSDesignSystem** as a separate SPM package only if Widget + macOS + iOS need independent release cycles

## Persistence consolidation

See **[architecture/mobile-infrastructure-roadmap.md](architecture/mobile-infrastructure-roadmap.md)** and the master plan Phase 2 for sync outbox + SQLite migrations.

Move stores into LookAfterData over time:

- Core: `MedicationStore`, `CycleLogStore`, etc. → `LookAfterData/Repositories/`
- ExecutiveBrain: `DecisionHistoryStore` → `LookAfterData/Storage/`
- LookAfterAI: `KeychainStore` → `LookAfterData/Security/` with `SecretsStoring` protocol in Core

## Dependency injection

- Introduce `Apps/LookAfter-iOS/Composition/AppDependencies.swift` for testable DI
- Wire `AnalyticsEnrichmentProviding` protocol if AI enrichment returns to Data layer

## CI

- GitHub Actions workflow in `Tools/ci/` — xcodebuild + swift test matrix

## Repository hygiene

- Resolve nested git repos (`ADHD/` parent vs `LifeOS/.git`) — single source of truth for contributors
