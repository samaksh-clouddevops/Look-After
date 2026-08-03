# Changelog

All notable structural changes to this repository are documented here.

## [Unreleased] — Repository Restructure

### Added
- Top-level folders: `Apps/`, `Config/`, `Documentation/`, `Scripts/`, `Tools/`, `Tests/`, `Assets/`
- Documentation: architecture ADRs, getting-started, build-and-test, package guide
- `.editorconfig`, `LICENSE`, `CONTRIBUTING.md`
- Package READMEs for LookAfterFeatures, LookAfterHealth, ExecutiveBrain

### Changed
- Moved app targets to `Apps/LookAfter-iOS`, `Apps/LookAfter-macOS`, `Apps/LookAfterWidget`
- Moved shared widget code to `Apps/Shared/`
- Moved config files to `Config/`
- Moved ADRs from `FlowOS/docs/adr/` to `Documentation/architecture/adr/`
- LookAfterCore: `UI/` → `DesignSystem/`
- LookAfterData: `Local/` → `Persistence/`; `WidgetDataStore` → `Storage/`
- LookAfterAI: reorganized into `GLM/`, `Memory/`, `Utilities/`
- ExecutiveBrain: engines → `Engine/`; `DecisionHistoryStore` → `Storage/`
- LookAfterFeatures: ViewModels moved into `ViewModels/` subfolders per feature
- Renamed `ExecutivePlanningEngine` → `LLMPlanningEngine`
- Moved `CognitiveModel` to LookAfterCore to decouple LookAfterData from LookAfterAI
- iOS app entry files → `Apps/LookAfter-iOS/App/`

### Removed
- Empty placeholder directories (Inbox, Health, Cache, Routing, Developer, LocalCache, etc.)
- Empty `FlowOS/` folder after doc migration
- Empty `Apps/LookAfter-iOS/Tests/`
