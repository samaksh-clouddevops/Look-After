# Changelog

All notable structural changes to this repository are documented here.

## [Unreleased] — Repository Restructure

### Added
- Top-level folders: `Apps/`, `Config/`, `Documentation/`, `Scripts/`, `Tools/`, `Tests/`, `Assets/`
- Documentation: architecture ADRs, getting-started, build-and-test, package guide
- `.editorconfig`, `LICENSE`, `CONTRIBUTING.md`
- Package READMEs for LifeOSFeatures, LifeOSHealth, ExecutiveBrain

### Changed
- Moved app targets to `Apps/LifeOS-iOS`, `Apps/LifeOS-macOS`, `Apps/LifeOSWidget`
- Moved shared widget code to `Apps/Shared/`
- Moved config files to `Config/`
- Moved ADRs from `FlowOS/docs/adr/` to `Documentation/architecture/adr/`
- LifeOSCore: `UI/` → `DesignSystem/`
- LifeOSData: `Local/` → `Persistence/`; `WidgetDataStore` → `Storage/`
- LifeOSAI: reorganized into `GLM/`, `Memory/`, `Utilities/`
- ExecutiveBrain: engines → `Engine/`; `DecisionHistoryStore` → `Storage/`
- LifeOSFeatures: ViewModels moved into `ViewModels/` subfolders per feature
- Renamed `ExecutivePlanningEngine` → `LLMPlanningEngine`
- Moved `CognitiveModel` to LifeOSCore to decouple LifeOSData from LifeOSAI
- iOS app entry files → `Apps/LifeOS-iOS/App/`

### Removed
- Empty placeholder directories (Inbox, Health, Cache, Routing, Developer, LocalCache, etc.)
- Empty `FlowOS/` folder after doc migration
- Empty `Apps/LifeOS-iOS/Tests/`
