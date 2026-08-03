# Brand Migration Report: LifeOS → Look After

Migration completed as a **branding-only** change. Package names, modules, types, folders, and bundle identifiers are unchanged.

## 1. Files modified

### Platform configuration
- [`project.yml`](../project.yml) — `CFBundleDisplayName`, permission strings
- [`Apps/LookAfter-iOS/Info.plist`](../Apps/LookAfter-iOS/Info.plist) — permission usage descriptions
- [`Apps/LookAfterWidget/Info.plist`](../Apps/LookAfterWidget/Info.plist) — widget display name

### Brand constant
- [`Packages/LookAfterCore/Sources/LookAfterCore/Companion/UserFacingCopy.swift`](../Packages/LookAfterCore/Sources/LookAfterCore/Companion/UserFacingCopy.swift)

### App UI (iOS)
- `Apps/LookAfter-iOS/Views/Auth/AuthView.swift`
- `Apps/LookAfter-iOS/Views/Onboarding/OnboardingView.swift`
- `Apps/LookAfter-iOS/Views/Settings/SettingsView.swift`
- `Apps/LookAfter-iOS/Views/Settings/APIKeysSettingsView.swift`
- `Apps/LookAfter-iOS/Views/Briefing/DailyBriefingCards.swift`
- `Apps/LookAfter-iOS/Views/Briefing/TodayCompactMetricsStrip.swift`
- `Apps/LookAfter-iOS/Views/Health/CycleDashboardView.swift`
- `Apps/LookAfter-iOS/Views/Health/CycleQuickLogSheet.swift`
- `Apps/LookAfter-iOS/Views/Shared/HealthSyncProgressView.swift`
- `Apps/LookAfter-iOS/Views/Modules/ModuleViews.swift`
- `Apps/LookAfter-iOS/Views/Insights/InsightsDashboardView.swift`
- `Apps/LookAfter-iOS/Services/HealthSyncService.swift`
- `Apps/LookAfter-iOS/Experience/AIExecutive/ExecutiveProfileView.swift`
- `Apps/LookAfter-iOS/Resources/example-life-profile.md`

### App UI (macOS + Widget)
- `Apps/LookAfter-macOS/LookAfterMacApp.swift`
- `Apps/LookAfter-macOS/Views/MacContentView.swift`
- `Apps/LookAfterWidget/FocusLiveActivity.swift`

### Package user-facing strings
- `Packages/LookAfterCore/Sources/LookAfterCore/Experience/ExperienceMode.swift`
- `Packages/LookAfterCore/Sources/LookAfterCore/Models/WidgetSnapshot.swift`
- `Packages/LookAfterAI/Sources/LookAfterAI/Prompts/LookAfterPrompts.swift` (prompt bodies only)
- `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Providers/GLMKeyManager.swift`
- `Packages/LookAfterFeatures/Sources/LookAfterFeatures/Tasks/ViewModels/DailyPlannerViewModel.swift`
- `Packages/LookAfterHealth/Sources/LookAfterHealth/HealthManager.swift`

### Documentation
- [`README.md`](../README.md) — product title and intro

## 2. User-facing strings updated (summary)

| Legacy name | Replacement | Context |
|-------------|-------------|---------|
| LifeOS | Look After | Settings, API keys, medical disclaimers, factory reset, AI prompts |
| FlowOS | Look After | iOS permission dialogs (Health, Calendar, Microphone, Speech) |
| ADHD Bitch | Look After | Auth splash, onboarding welcome, Settings About, Health sync UI, macOS menu bar, widget display name |

Central constant: `UserFacingCopy.productName = "Look After"`

Medical disclaimers unified via `UserFacingCopy.medicalDisclaimer` and `medicalDisclaimerWithProvider`.

## 3. Internal occurrences intentionally left unchanged

| Category | Examples |
|----------|----------|
| Swift modules | `import LookAfterCore`, `import LookAfterAI`, … |
| Types | `LookAfterApp`, `LookAfterMasterCanvas`, `LookAfterTab`, `LookAfterPrompts` |
| Targets | `LookAfter-iOS`, `LookAfter-macOS`, `LookAfterWidget` |
| Bundle IDs | `com.samaksh.flowos.app` |
| Notification names | `LifeOSTaskListDidChange`, `LookAfterHealthKitDataDidChange` |
| Developer comments | `/// LifeOS Design System`, `/// A task in the LifeOS system` |
| Repo / Xcode paths | `LookAfter.xcodeproj`, `Apps/LookAfter-iOS/` |
| Developer docs | `Documentation/qa/*`, ADRs, architecture guides |
| Test fixtures | Synthetic task titles in integration tests |

## 4. Build status

Run after migration:

```bash
xcodegen generate
xcodebuild -scheme LookAfter-iOS -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme LookAfter-macOS -destination 'platform=macOS' build
```

(See validation section in commit/CI for actual results.)

**Verified:** iOS build succeeded, macOS build succeeded. LookAfterCore tests: 153/160 pass (7 pre-existing flaky/date failures unrelated to branding). Grep gate: no user-facing legacy brand strings in Apps/ or package Sources/.

## 5. Screens requiring manual review

| Screen | What to verify |
|--------|----------------|
| Auth splash | Title shows **Look After** |
| Onboarding welcome | "Welcome to Look After" |
| Settings → About | "About Look After" |
| Settings → Widgets | Widget search instructions mention Look After |
| Health permission flow | System dialog says "Look After" wants to read Health |
| Health sync progress | All step labels use Look After |
| Widget gallery | Extension name **Look After** |
| macOS menu bar | Menu bar extra title **Look After** |
| Factory reset alert | "Factory Reset Look After?" |
| AI Coach | Coach introduces itself as Look After (via updated prompts) |

## 6. Remaining inconsistencies

- **Health app cached name:** Settings → Health may show the old display name until delete/reinstall (bundle ID unchanged).
- **App Store / TestFlight listing:** Out of repo scope; update manually when publishing.
- **GitHub repo name:** Still `samaksh-clouddevops/LifeOS` — engineering repo name, not user-facing.
- **ATTENTION_OS_SPEC.md:** Historical spec still references FlowOS/LifeOS — developer doc, not updated per migration rules.
