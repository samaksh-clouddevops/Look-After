# Changelog

All notable structural changes to this repository are documented here.

## [0.1.0-alpha] — 2026-08-09 (First Alpha)

First public alpha of Look After. See [Documentation/releases/0.1.0-alpha.md](Documentation/releases/0.1.0-alpha.md).

### Added
- Proactive AI phase 2: moment agents, bundles, BG notifications, speech, accountability
- Azure auth-proxy with product-key licensing; proxy-only GLM/TTS (no client API keys)
- Timeline drag-replan, capture router, contextual replan sheets, SQLite task store
- Weekly Review debrief, health connection status, manual sleep logging, widget shortcuts
- Auth-proxy service under `services/auth-proxy/` with Azure Bicep + deploy scripts

### Changed
- Removed in-app API key settings; AI requires license + auth proxy
- Sign in with Apple moved to production entitlements (Personal Team dev builds use base entitlements)
- Initiation-bridge nudge debouncing (foreground count + speech cooldown)

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
