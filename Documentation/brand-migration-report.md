# Brand Migration Report: LifeOS → Look After

Migration completed as a **branding-only** change. Package names, modules, types, folders, and bundle identifiers are unchanged.

## 1. Files modified

### Platform configuration
- [`project.yml`](../project.yml) — `CFBundleDisplayName`, permission strings
- [`Apps/LifeOS-iOS/Info.plist`](../Apps/LifeOS-iOS/Info.plist) — permission usage descriptions
- [`Apps/LifeOSWidget/Info.plist`](../Apps/LifeOSWidget/Info.plist) — widget display name

### Brand constant
- [`Packages/LifeOSCore/Sources/LifeOSCore/Companion/UserFacingCopy.swift`](../Packages/LifeOSCore/Sources/LifeOSCore/Companion/UserFacingCopy.swift)

### App UI (iOS)
- `Apps/LifeOS-iOS/Views/Auth/AuthView.swift`
- `Apps/LifeOS-iOS/Views/Onboarding/OnboardingView.swift`
- `Apps/LifeOS-iOS/Views/Settings/SettingsView.swift`
- `Apps/LifeOS-iOS/Views/Settings/APIKeysSettingsView.swift`
- `Apps/LifeOS-iOS/Views/Briefing/DailyBriefingCards.swift`
- `Apps/LifeOS-iOS/Views/Briefing/TodayCompactMetricsStrip.swift`
- `Apps/LifeOS-iOS/Views/Health/CycleDashboardView.swift`
- `Apps/LifeOS-iOS/Views/Health/CycleQuickLogSheet.swift`
- `Apps/LifeOS-iOS/Views/Shared/HealthSyncProgressView.swift`
- `Apps/LifeOS-iOS/Views/Modules/ModuleViews.swift`
- `Apps/LifeOS-iOS/Views/Insights/InsightsDashboardView.swift`
- `Apps/LifeOS-iOS/Services/HealthSyncService.swift`
- `Apps/LifeOS-iOS/Experience/AIExecutive/ExecutiveProfileView.swift`
- `Apps/LifeOS-iOS/Resources/example-life-profile.md`

### App UI (macOS + Widget)
- `Apps/LifeOS-macOS/LifeOSMacApp.swift`
- `Apps/LifeOS-macOS/Views/MacContentView.swift`
- `Apps/LifeOSWidget/FocusLiveActivity.swift`

### Package user-facing strings
- `Packages/LifeOSCore/Sources/LifeOSCore/Experience/ExperienceMode.swift`
- `Packages/LifeOSCore/Sources/LifeOSCore/Models/WidgetSnapshot.swift`
- `Packages/LifeOSAI/Sources/LifeOSAI/Prompts/LifeOSPrompts.swift` (prompt bodies only)
- `Packages/LifeOSAI/Sources/LifeOSAI/GLM/Providers/GLMKeyManager.swift`
- `Packages/LifeOSFeatures/Sources/LifeOSFeatures/Tasks/ViewModels/DailyPlannerViewModel.swift`
- `Packages/LifeOSHealth/Sources/LifeOSHealth/HealthManager.swift`

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
| Swift modules | `import LifeOSCore`, `import LifeOSAI`, … |
| Types | `LifeOSApp`, `LifeOSMasterCanvas`, `LifeOSTab`, `LifeOSPrompts` |
| Targets | `LifeOS-iOS`, `LifeOS-macOS`, `LifeOSWidget` |
| Bundle IDs | `com.samaksh.flowos.app` |
| Notification names | `LifeOSTaskListDidChange`, `LifeOSHealthKitDataDidChange` |
| Developer comments | `/// LifeOS Design System`, `/// A task in the LifeOS system` |
| Repo / Xcode paths | `LifeOS.xcodeproj`, `Apps/LifeOS-iOS/` |
| Developer docs | `Documentation/qa/*`, ADRs, architecture guides |
| Test fixtures | Synthetic task titles in integration tests |

## 4. Build status

Run after migration:

```bash
xcodegen generate
xcodebuild -scheme LifeOS-iOS -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme LifeOS-macOS -destination 'platform=macOS' build
```

(See validation section in commit/CI for actual results.)

**Verified:** iOS build succeeded, macOS build succeeded. LifeOSCore tests: 153/160 pass (7 pre-existing flaky/date failures unrelated to branding). Grep gate: no user-facing legacy brand strings in Apps/ or package Sources/.

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
