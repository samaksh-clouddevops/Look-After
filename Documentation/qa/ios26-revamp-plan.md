# iOS 26 revamp plan

**Document ID:** QA-IOS26-01  
**Date:** 9 September 2026  
**Status:** Phase D landed (9 Sep 2026) — DesignSystem V5 (chrome glass vs content opaque). Phases A–C remain landed.  
**Related:** [01-test-strategy.md](01-test-strategy.md), [04-screen-test-cases.md](04-screen-test-cases.md), [10-accessibility-checklist.md](10-accessibility-checklist.md), [timeline-complete-fix-plan.md](timeline-complete-fix-plan.md)

This is the program to raise Look After’s **minimum OS to iOS 26 / macOS 26**, then rebuild chrome, motion, and look using Apple’s Liquid Glass system and the [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) catalog. Domain logic (timeline clocks, Brain, HealthKit math, auth-proxy) is **not** rewritten.

---

## 0. Locked product decisions

| Topic | Decision |
|---|---|
| Minimum OS | **iOS 26** and **macOS 26**. Drop iOS 17–25 and macOS 14–25. No long-term `#available(iOS 26, *)` forks once the bump ships. |
| Look | Adopt **Liquid Glass** for chrome and controls. Content (cards, lists, timeline rows) stays **opaque and calm**. Glass is not a wallpaper. |
| Motion | One motion language: **snappy springs** for chrome, **numeric/symbol content transitions** for clocks and NOW, **matched geometry / navigation zoom** for task → detail. ADHD-first: Reduce Motion must flatten this to opacity/instant. |
| Custom tab bar | Replace `LookAfterBottomNav`’s opaque bar with **system glass**. Keep the center **Capture** action. Prefer native `TabBar` / `Tab` APIs plus a glass Capture control over painting a fake material. |
| Design tokens | Evolve `DesignSystem` (V4 → **V5**). Fake `surfaceGlass` opacity layers go away; real `.glassEffect()` / `.buttonStyle(.glass)` take their place. |
| Skills | Every visual/animation PR reads Paul Hudson **and** the matching dpearson skill (`swiftui-liquid-glass`, `swiftui-animation`, `swiftui-gestures`, `widgetkit`, `activitykit`, `ios-accessibility`). |
| What we do not rebuild | SQLite clocks, `SemanticPlacementSense`, Executive Brain, Firestore replica rules, auth-proxy, medication safety. Those stay; they just get a new shell. |
| ADHD visual load | Fewer simultaneous glass surfaces than a typical Apple demo. One `GlassEffectContainer` per chrome cluster. No looping `.bouncy` on the timeline. |

---

## 1. Current baseline (what we are leaving)

| Layer | Today |
|---|---|
| Targets | iOS **17.0**, macOS **14.0** (`project.yml`, all `Package.swift`, widget, tests) |
| Language | Swift **5.9**, tools-version 5.9 |
| Shell | `ExperienceRootView` → `LookAfterRootCanvas` → custom `LookAfterBottomNav` (HStack + `backgroundSecondary`) |
| Tabs | Briefing, Today, Review, Capture, Brain, You |
| Surfaces | 47 screens in [04-screen-test-cases.md](04-screen-test-cases.md) |
| Design | `DesignSystem` V4: hex adaptive colors, `surfaceGlass` as opacity, linear “gradients” that are actually flat |
| Extensions | Widget + Live Activities, app group `group.com.samaksh.flowos` |
| Tests | XCTest-heavy packages; QA framework assumes iOS 17+ |

---

## 2. Migration steps

Work in this order. Do not start screen polish before the toolchain bump compiles. Do not start animation choreography before chrome is glass.

### Phase A — Toolchain and OS floor

**Goal:** The app **only** builds for iOS 26 / macOS 26.

| Step | Work | Where |
|---|---|---|
| A1 | Install **Xcode 26** (or current GM that ships the iOS 26 SDK). Confirm `xcodebuild -version` and simulators named for iOS 26. | Machine / CI images |
| A2 | Bump `deploymentTarget` iOS `26.0`, macOS `26.0` in `project.yml` for app, widget, and any test targets. | `project.yml` then `xcodegen generate` |
| A3 | Bump every package: `platforms: [.iOS(.v26), .macOS(.v26), …]`, `swift-tools-version` to the Xcode-26 default (6.2 / 6.3). | `Packages/*/Package.swift` |
| A4 | Set `SWIFT_VERSION` to 6.x in `project.yml`. Turn on **strict concurrency** for app + packages (warnings → errors in a follow-up if the first compile is too noisy). | `project.yml`, package `swiftSettings` |
| A5 | Update CI (`Tools/ci`, GitHub workflows) destinations from `iPhone 17` + iOS 17 assumptions to **iOS 26 simulators**. | `.github/workflows/*`, `Documentation/build-and-test.md` |
| A6 | App Store / Info: confirm live activities, HealthKit, calendar usage strings still valid; add any iOS 26 privacy manifest deltas. | `Info.plist`, privacy manifests |
| A7 | Drop dead `#available(iOS 17/18/26)` branches that exist only to support old OS. Keep 18+ APIs that we already use (zoom, symbol wiggle) as the baseline. | Grep `#available` |

**Exit:** `xcodebuild -scheme LookAfter-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` succeeds.

**Phase A notes (landed):**

- Machine / CI: Xcode 26.6, iOS 26.5 SDK, GitHub `macos-26` runners, simulator `iPhone 17`.
- At Phase A land, `SWIFT_VERSION` on the app was **5.9** and packages used `.swiftLanguageMode(.v5)`. Phase B turned those on to Swift 6.
- Shared caches (`MedicationStore`, `LifeModelStore`, `UserLifeProfileStore`, `FreshInstallGuard`, shortcut queue) now use `Mutex` so they are Swift 6-ready.
- HealthKit query timeouts resume **Sendable** values (sleep inputs, doubles, workout summaries), not `HKWorkout` / `HKStatistics` across isolation.
- Dead `#available(iOS 13…18)` / `@available(iOS 17)` branches unwrapped.
- Usage strings (HealthKit, calendar, mic, speech, Live Activities) unchanged. No new iOS 26 privacy keys required for this bump. `PrivacyInfo.xcprivacy` is still absent (pre-existing App Store follow-up).
- Linux Docker harnesses (`TourPlacementHarness`, `PerformanceBudgetHarness`) stay macOS 13 / tools 5.9 so they can still run off Apple SDKs.

### Phase B — Compile and concurrency harden

**Goal:** Swift 6 isolation is honest; no `@unchecked Sendable` dumps.

| Step | Work | Skill |
|---|---|---|
| B1 | Fix isolation errors in `LookAfterFeatures` / `LookAfterAI` (MainActor VMs, GLM callbacks). | `swift-concurrency-pro` + dpearson `swift-concurrency` |
| B2 | Make Core scheduling types stay `Sendable` value types (already the model). | same |
| B3 | Tests: migrate **new** tests to Swift Testing; leave XCTest only where UI tests require it. | `swift-testing-pro` + dpearson `swift-testing` |

**Exit:** iOS + macOS build **and** `swift test` for Core/Features/AI with zero concurrency errors.

**Phase B notes (landed):**

- App `SWIFT_VERSION` is **6.0** with `SWIFT_APPROACHABLE_CONCURRENCY`. `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` on LookAfter-iOS, LookAfterWidget, and LookAfter-macOS only (not unit-test bundles, not Core).
- Packages use `.swiftLanguageMode(.v6)` + `NonisolatedNonsendingByDefault`. LookAfterFeatures (library, not its XCTest target) also uses `.defaultIsolation(MainActor.self)`.
- Honest isolation: GLM briefing completions are `@Sendable`; `PersonalAnalyticsEngineProtocol` is `@MainActor`; App Intent metadata is `static let`; HealthKit timeouts reuse public `AsyncTimeout` (`T: Sendable`); speech/location delegates hop to MainActor instead of sending non-Sendable handles.
- macOS now compiles shared Brain/Inbox/Tasks screens by including speech/TTS sources and dropping the iOS-only `AppShellState` environment object from `ReschedulePreviewSheet` (pass `TasksViewModel` instead).
- New Swift Testing: `MutexHotPathStoreTests` (Core) and parameterized `InsightsTimeframeSwiftTestingTests` (Features). Existing XCTest stays.
- Verified: LookAfter-iOS (`iPhone 17, OS=26.5`) and LookAfter-macOS both `CODE_SIGNING_ALLOWED=NO` **BUILD SUCCEEDED**. `swift test` LookAfterAI: 26 passed. LookAfterCore: no concurrency errors (one pre-existing `HealthSummaryFreshnessTests` assertion vs the 36h last-night heuristic). LookAfterFeatures: compiles/runs under Swift 6; three PerPage schedule assertions still fail and are not concurrency diagnostics.

### Phase C — System chrome (Liquid Glass for free, then custom)

**Goal:** Navigation, sheets, toolbars look like iOS 26 before we restyle cards.

Apple applies glass to standard bars automatically on the iOS 26 SDK. Our custom tab bar **blocks** that.

| Step | Work | Files / skill |
|---|---|---|
| C1 | Inventory every custom bar, overlay, and `.ultraThinMaterial` / `surfaceGlass`. | Grep `LookAfterBottomNav`, `DesignSystem.surfaceGlass`, `.material`, `.toolbar` |
| C2 | Rebuild root chrome: `TabView` / `Tab` with glass tab bar **or** `GlassEffectContainer` around a slim custom bar. Preserve Capture in the center. | `LookAfterRootCanvas`, `LookAfterBottomNav`, `ExperienceRootView` · `swiftui-liquid-glass` |
| C3 | Sheets and inspectors: let system glass present; remove extra dimming layers that fight the material. | Executive assistant sheet, capture, task editor |
| C4 | Toolbars: `.buttonStyle(.glass)` / `.glassProminent` for Capture and primary actions; `ToolbarSpacer` where groups split. | Capture, Briefing pull, timeline actions |
| C5 | Scroll edges: `scrollEdgeEffectStyle` on Briefing, Today rail, task lists so content fades into the glass bar. | Timeline, briefing, task list |
| C6 | `backgroundExtensionEffect` only if a hero (Briefing) needs the background under the status bar. Do not put it on every screen. | Briefing |

**Exit:** Five tabs + Capture look native on iPhone 26. Capture still one tap from anywhere.

**Phase C notes (landed):**

- Kept custom `LookAfterBottomNav` (not `TabView`) so center Capture, tour anchors, and ADHD overlay hide still work. One `GlassEffectContainer` wraps the bar; Reduce Transparency falls back to opaque `backgroundSecondary`.
- Capture uses `.buttonStyle(.glassProminent)` with accent tint; Capture sheet Save / dismiss FAB also glass-prominent.
- Executive assistant panel uses `.glassEffect` (opaque fallback when Reduce Transparency); dismiss scrim lightened from heavy `shadowElevated` to `Color.black.opacity(0.22)`.
- ADHD emergency dock is a glass capsule cluster with prominent Voice.
- `scrollEdgeEffectStyle(.soft, for: .bottom)` on Briefing, Today, and task list.
- Skipped `backgroundExtensionEffect` — Briefing already sits on full-bleed `PremiumBackground` with safe-area padding; no hero media under the status bar yet.
- Verified: LookAfter-iOS (`iPhone 17, OS=26.5`) **BUILD SUCCEEDED**.

### Phase D — Design system V5

**Goal:** One token set that matches Liquid Glass; ADHD calm on content.

| Step | Work |
|---|---|
| D1 | Split tokens: **chrome** (glass, interactive) vs **content** (opaque cards, timeline rows, text). |
| D2 | Retire `surfaceGlass` opacity hacks. Content cards use `backgroundSecondary` / elevated fills, not glass. |
| D3 | Accent stays the existing green (`5A9E3F`) as a **tint on glass buttons**, not a flood fill. |
| D4 | Dark / light: verify contrast on glass over Briefing photography/color. Clear glass gets a dimming layer if needed. |
| D5 | Document in `DesignSystem.swift` and a short `Documentation/design/ios26-chrome.md` (shapes, when to use `.regular` vs `.clear` vs no glass). |

**Exit:** New screens cannot compile in a “third material” — only chrome glass or content opaque.

**Phase D notes (landed):**

- `DesignSystem` is **V5**: `contentSurface` / `contentSurfaceSubtle` / `contentSurfaceElevated` for opaque content; `LookAfterChrome` for accent tint, clear-glass dimming, and overlay scrim.
- `surfaceGlass` / `borderGlass` deprecated (aliases to opaque content / border).
- `ElevatedSurface` / `DestinationTile` / briefing section cards no longer use translucent opacity fills.
- Shared chrome: toolbar cluster, toasts, health-sync compact banner use real glass; Capture / tab Capture / dismiss FAB tint via `LookAfterChrome.accentTint`.
- Guide: [Documentation/design/ios26-chrome.md](../design/ios26-chrome.md).
- Verified: LookAfter-iOS (`iPhone 17, OS=26.5`) **BUILD SUCCEEDED**.

### Phase E — Screen revamp (look)

Do **one tab at a time**. Do not restyle all 47 surfaces in one PR.

| Order | Surfaces (from QA S-ids) | Look notes |
|---|---|---|
| E1 | S01–S04 root + nav | Done in C; verify tour frames still attach. |
| E2 | S06 Briefing | Hero, capacity card, pull-to-refresh; glass on actions only. |
| E3 | S05 / S10 Today + live timeline | Keep clock rail logic; restyle rows, NOW, LATE. No glass on every row. |
| E4 | Capture / S11 assistant | Glass Capture morph to sheet (`glassEffectID` + `.matchedGeometry`). |
| E5 | S14–S18 tasks | List, daily plan, stacks, reschedule preview. |
| E6 | S19–S20 Brain | Inspector chrome; keep decision copy. |
| E7 | S21, S25, S26 You / settings / onboarding / auth | Onboarding can use more motion; auth stays high contrast. |
| E8 | S30–S33 ADHD emergency / focus / decide / reset | **Less** glass. High contrast, large hit targets. |
| E9 | S35–S37 health / cycle | Same content rules. |
| E10 | Modules grid + module templates | Shared card component, not per-module snowflakes. |
| E11 | macOS S46–S47 | macOS 26 glass window chrome; do not clone the iPhone tab bar. |

**Exit:** Each row has a screenshot pair (before/after) and a11y pass (Phase T).

**Phase E notes (in progress):**

- **E1:** Verified — `LookAfterBottomNav` still has `.featureTourAnchor` on all five tabs + Capture; `TourTabBarFrameReader` present.
- **E2:** Briefing content → opaque `contentSurface*` (executive card, glance row, habit/health mini tiles, module insights, health banner, life gaps). Chrome only: header Capture/Customize/Settings `.glass`, Continue / Replan / health primary `.glassProminent` + accent tint, scroll hint glass with Reduce Transparency fallback. `.refreshable` kept. No glass on section/card bodies.
- **E3:** Timeline row fills → opaque surfaces by phase (no translucent elevated fills); conflict uses stroke, not tint wash fill. Today header / context chips / Plan / Start now / empty Capture → glass chrome. Metrics strip + journal field/tiles opaque; journal mic glass.
- **E4:** Capture tab → sheet zoom morph via shared `@Namespace` (`matchedTransitionSource` + `.navigationTransition(.zoom)`); Capture button tagged `glassEffectID`. Composer field opaque `contentSurface`; mic/chips/Save stay glass chrome. Assistant panel wrapped in `GlassEffectContainer` + `glassEffectID` for expand continuity.
- **E5:** Tasks list header + create/import/stack toggle → glass chrome; filter/tag chips + weekday picks use opaque `contentSurfaceSubtle` (no white opacity fills). Stack Done/Defer and task action primary → glass; Daily Plan Adjust + Import CTA + Reschedule Apply/Regenerate → glass. Reschedule/plan cards stay `.elevatedSurface` opaque. Scheduling math untouched.
- **E6:** Brain Decide/Ask chrome → glass; inspector Refresh + section chips + blocks → opaque `contentSurface*` (decision copy unchanged).
- **E7:** You / Settings / License / GLM / onboarding / auth — list rows and fields → `contentSurface*`; primary CTAs glass; auth scrims → `LookAfterChrome.overlayScrim`.
- **E8:** ADHD emergency/focus/reset content → opaque `contentSurfaceElevated` (less glass). Dock keeps glass; Reduce Transparency → solid elevated + border.
- **E9:** Cycle dashboard/quick log + health verification cards → opaque surfaces; quickLog/Save/Retry → glassProminent.
- **E10:** Modules grid gear glass; journal/calendar/travel/learning/creativity/home templates drop white-opacity snowflakes for `contentSurface*`.
- **E11:** macOS keeps `NavigationSplitView` (no iPhone tab bar); unified window toolbar + visible system glass chrome; settings rows → `contentSurface`.
- **Phase E complete** through E11. Next phases: F motion, G widgets, I a11y, J ship.

### Phase F — Motion language (animation)

**Goal:** The app *feels* iOS 26 without nauseating ADHD users.

Skill: `swiftui-animation`.

| Step | Motion | Where |
|---|---|---|
| F1 | Tab / Capture symbol `.replace` / `.bounce` (discrete, value-triggered). | Tab bar, Capture |
| F2 | NOW clock and remaining minutes: `.contentTransition(.numericText)` + `.snappy`. | Timeline, briefing hero, widgets |
| F3 | Task row → detail: `matchedTransitionSource` + `.navigationTransition(.zoom)` (iOS 18+ now baseline). | Task list, timeline row |
| F4 | Capture expand: `GlassEffectContainer` + `glassEffectID` morph, **not** a custom matched-geometry card unless zoom is enough. | Capture |
| F5 | Complete-NOW: symbol `.checkmark` replace + row collapse transition. | Timeline |
| F6 | `PhaseAnimator` only for Focus session breathe — gated on `accessibilityReduceMotion`. | Focus |
| F7 | Ban: `DispatchQueue.main.asyncAfter` to start animations; bare `.animation(.easeIn)` without a value; looping bouncy on Today. |

**Exit:** Reduce Motion on → no springs, no morph, no zoom; screens still usable.

**Phase F notes (landed):**

- **F1:** Tab + Capture discrete `.symbolEffect(.bounce)` (value-triggered); selection uses `PremiumMotion.spring(reduceMotion:)`.
- **F2:** NOW clock / remaining / briefing metrics / widgets use `.contentTransition(.numericText)` + `PremiumMotion.snappy(reduceMotion:)`.
- **F3:** Task list/stack → edit sheets use `lookAfterZoomSource` / `lookAfterZoomDestination` (Reduce Motion disables zoom). Timeline edit still opens task list (no invented detail destination).
- **F4:** Capture zoom via `CaptureSheetZoomModifier`; morph source/ID skipped when Reduce Motion.
- **F5:** Complete-NOW checkmark bounce + spring-wrapped complete; DONE transition.
- **F6:** Focus breathe = `PhaseAnimator` glow (static under Reduce Motion); Body Doubling loops gated off.
- **F7:** Animation `asyncAfter` replaced with completion/`Task.sleep` where choreography; scroll chevron repeating bounce gated; tour/settings delays kept intentional.
- Added `PremiumMotion.snappy(reduceMotion:)`.

### Phase G — Widgets, Live Activities, Control Center

| Step | Work | Skill |
|---|---|---|
| G1 | Rebuild Now / Energy widgets on iOS 26 widget chrome (Liquid Glass on Home Screen is system-owned). | `widgetkit` |
| G2 | Live Activity / Dynamic Island: update colors and compact/expanded for glass lock screen. | `activitykit` |
| G3 | Optional: Control Center **Start Focus** / **Capture** controls if App Intents already exist. | `app-intents`, `widgetkit` |
| G4 | Confirm app group + snapshot restamp still fires when completing NOW (timeline plan T-42 behavior). | Existing `TimelineService` |

**Exit:** Widget + Island match the app; completing NOW still restamps.

**Phase G notes (landed):**

- **G1:** Now / Energy / Tasks widgets use V5 surfaces + brand accent; `widgetRenderingMode` + `.widgetAccentable()` for Liquid Glass; Energy adds accessory Rectangular/Inline Gauge families.
- **G2:** Focus + NowPin Live Activities — opaque lock-screen plate, `5A9E3F` accent, solid chips (no white-opacity washes), numeric transitions on %/timers; ActivityAttributes untouched.
- **G3:** Control Center `LookAfterCaptureControl` + `LookAfterStartFocusControl`; `PendingShortcutAction.openCapture` + `WidgetOpenCaptureIntent` / App Shortcut; Start Focus reuses `WidgetStartHeroTaskIntent`.
- **G4:** Completing NOW already called `refreshWidgetData(..., immediateTimelineRebuild: true)` (T-42). Fixed fingerprint short-circuit: immediate sync uses `force: true` so widgets + pin always reload.

### Phase H — Optional iOS 26 frameworks (only if product wants them)

Do **not** block the look revamp on these.

| Framework | Adopt? | Why / why not |
|---|---|---|
| AlarmKit | Maybe later | Wind-down / wake as system alarms — high value, separate epic |
| Foundation Models (on-device) | No for v1 of this revamp | GLM + auth-proxy stay the brain; on-device is a later privacy track |
| PaperKit / PencilKit | No | Not core |
| App Intents refresh | Yes, small | Spotlight / Shortcuts for Capture and Focus |
| TipKit | Maybe | One-shot chrome coach marks; don’t fight the existing tour |

### Phase I — Accessibility and ADHD pass

Skill: `ios-accessibility` + existing [10-accessibility-checklist.md](10-accessibility-checklist.md).

| Step | Work |
|---|---|
| I1 | Reduce **Transparency**: glass becomes solid; text contrast still AA. |
| I2 | Reduce **Motion**: see F7. |
| I3 | Increase Contrast / Bold Text / Dynamic Type xxxLarge on Briefing + Today + Capture. |
| I4 | VoiceOver: tab bar, Capture, NOW, LATE, drag handles — labels must not say “glass”. |
| I5 | Hit targets ≥ 44 pt on glass buttons (glass chrome often looks smaller than it is). |

**Phase I notes (landed):**

- **I1:** Reduce Transparency opaque fallbacks for toasts, health-sync compact card, auth loading (match tab bar / dock pattern).
- **I2:** Emergency pulse + reset breathe gated; toast/timeline expand use `PremiumMotion.spring(reduceMotion:)` (F gates already covered Capture zoom / Focus PhaseAnimator / tab bounce).
- **I3:** Briefing/Today/Capture/Focus — relative/`@ScaledMetric` fonts + `minimumScaleFactor` on hero/name/timer/scores; greeting supporting copy → `textSecondary` for Increase Contrast. Full `LookAfterTypography` Dynamic Type migration deferred.
- **I4:** Assistant drag handle → “Collapse planning assistant” + button trait + collapse action (never “glass”); reset dismiss labeled; timeline title includes NOW/LATE/DONE; Briefing header Capture/Customize/Settings already labeled; emergency exit → “Exit emergency mode”.
- **I5:** `DesignSystem.minTouchTarget` (44) on bottom nav tabs/Capture, Capture mic/chips, Today context + All tasks chips, metrics expand chevron (visual 28pt, hit 44), ADHD dock Voice, Focus ±5 min.

Device sign-off (VoiceOver / XXXL / Inspector contrast) still recommended before ship (Phase J).

### Phase J — Ship

| Step | Work |
|---|---|
| J1 | Update App Store screenshots and preview video for iOS 26. | [app-store-optimization](https://github.com/dpearson2699/swift-ios-skills) |
| J2 | Review notes: “Requires iOS 26”; Health / calendar / mic strings unchanged in spirit. | `app-store-review` |
| J3 | Release checklist [12-release-checklist.md](12-release-checklist.md) with OS floor updated. |

**Phase J notes (landed — docs / gates; ASC upload is human):**

- **J1:** Shot list + preview beats → [Documentation/releases/ios26-screenshot-shot-list.md](../releases/ios26-screenshot-shot-list.md). Capture on physical iOS 26; ASC upload still required.
- **J2:** Review notes template → [Documentation/releases/app-store-review-notes-ios26.md](../releases/app-store-review-notes-ios26.md). Permission strings unchanged in spirit. `PrivacyInfo.xcprivacy` called out as open GA follow-up.
- **J3:** QA-12 gains **iOS 26 / Liquid Glass ship gate**; ship index → [Documentation/releases/ios26-ship.md](../releases/ios26-ship.md). Alpha release notes + performance reference device updated to iOS 26 floor.

**Program status:** Phases **A–J** complete for engineering deliverables. Remaining: fill demo credentials, capture/upload screenshots, run QA-12 checkboxes, TestFlight soak, App Store submit.

---

## 3. What we explicitly will not do in this program

- Rewrite `SemanticPlacementSense`, NOW resolver, or Firestore merge rules.
- Put `.glassEffect()` on every timeline row or every Brain card.
- Ship iOS 26 UI while still supporting iOS 17 (`#available` as a permanent dual design).
- Adopt Liquid Glass as a full-screen blur behind dense text (legibility + ADHD load).

---

## 4. Suggested PR slicing

Keep PRs reviewable. Example sequence:

1. A1–A7 toolchain only (no UI).  
2. B concurrency.  
3. C2 tab bar + Capture (the highest-risk visual).  
4. D tokens.  
5. E2 Briefing.  
6. E3 Today / timeline.  
7. F motion on those two tabs.  
8. E4 Capture morph.  
9. Remaining E tabs.  
10. G widgets / Island.  
11. I a11y sweep.  
12. J store.

---

## 5. Testing plan

This extends QA-01. Until Phase A lands, existing iOS 17 tests remain the safety net for **behavior**. After A, all automated tests run on **iOS 26 simulators**.

### 5.1 Test strategy changes

| Old (QA-01) | New |
|---|---|
| Platforms iOS 17+ / macOS 14+ | **iOS 26 / macOS 26 only** |
| Custom nav treated as stable chrome | Chrome is **in play** — regression every tab switch |
| Accessibility: Reduce Motion | Add **Reduce Transparency** as equal P0 (glass) |
| Performance: UI lag scorecard (QA-37) | Re-run on glass + timeline scroll |
| Visual: informal screenshots | Required **before/after** per Phase E row |

Do not weaken Brain / timeline / HealthKit tests to make UI PRs green.

### 5.2 Automation (CI)

| Gate | Command / artifact | When |
|---|---|---|
| T-A | iOS 26 simulator `xcodebuild build` LookAfter-iOS + widget | Every PR after A |
| T-B | macOS 26 `xcodebuild build` LookAfter-macOS | Every PR after A |
| T-C | `swift test` LookAfterCore, Features, AI, Data, Health, ExecutiveBrain | Every PR |
| T-D | Existing timeline / placement / NOW tests (`SemanticPlacementSense`, `TimelineNowResolver`, drag) | Every PR — **must stay green** |
| T-E | Decision regression (QA-22) | Main and release |
| T-F | New Swift Testing cases for DesignSystem V5 helpers (contrast, reduce-motion mapping) | From D onward |

CI destination example (update when the simulator name is final):

```bash
xcodebuild -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' \
  test
```

### 5.3 Visual and interaction QA (manual + snapshot)

Run on a **physical iPhone on iOS 26** for glass (simulator glass is a hint, not truth).

**Per tab (Briefing, Today, Review, Brain, You) plus Capture:**

| ID | Check |
|---|---|
| V1 | System / custom tab bar reads as Liquid Glass, not a gray rectangle |
| V2 | Capture is obvious, 44 pt, morphs or presents without jumping |
| V3 | Scroll: `scrollEdgeEffect` does not hide the NOW chip or primary CTA |
| V4 | Sheets inherit glass; content inside stays readable |
| V5 | Dark and light both pass contrast on glass tints |
| V6 | No glass on timeline rows / task titles |
| V7 | Animation: tab change, complete task, NOW tick — Reduce Motion off |
| V8 | Same flows with Reduce Motion **on** (no zoom, no morph) |
| V9 | Reduce Transparency **on** (solid bars, no missing buttons) |
| V10 | Dynamic Type XXXL: Briefing + Today + Capture still usable |

Map V-checks to S-ids in [04-screen-test-cases.md](04-screen-test-cases.md) as you complete each E-row (S06, S10, etc.).

**Snapshot (optional but recommended from E2):** iOS 26 snapshots for Briefing, Today rail, tab bar, Capture. Store in `Tests/` with `UITraitCollection` variants: light/dark, reduce motion, reduce transparency.

### 5.4 Behavioral regression (must not regress)

Copied from the timeline program — these are **CI-blocking**, not visual:

- Dinner cannot sit at 10:00; grocery not at night; gym not immediately after a meal.  
- NOW: overdue incomplete work beats Wind down; Wind down only after 17:00.  
- Completing NOW restamps widgets / pin / briefing from the same snapshot.  
- Paint from SQLite + memory; Firestore is replica.  
- Calendar occupies; tasks shift.

If a glass PR breaks any of these, revert the UI change.

### 5.5 Performance

| Probe | Target | Tool |
|---|---|---|
| Today timeline scroll (30+ rows, one glass tab bar) | No dropped frames on a current iPhone | Instruments / QA-37 scorecard |
| Glass count | One container for tab+Capture; not per row | Code review + `swiftui-liquid-glass` checklist |
| Briefing open | Comparable to pre-revamp | os_signpost / MetricKit later |
| Live Activity update | Completing NOW still < 1s to Island | Manual |

### 5.6 Accessibility test matrix

| Setting | Briefing | Today | Capture | Brain | You |
|---|---|---|---|---|---|
| Default | V1–V7 | V1–V7 | V2, V7 | V1, V4 | V1, V4 |
| Reduce Motion | V8 | V8 | V8 | V8 | V8 |
| Reduce Transparency | V9 | V9 | V9 | V9 | V9 |
| VoiceOver | headings, NOW, LATE | row + drag | button traits | inspector | settings |
| Dynamic Type XXXL | V10 | V10 | V10 | sample | sample |

Emergency / Focus (S30–S33): **P0** on contrast and Reduce Motion; glass is optional there.

### 5.7 Device / OS matrix

| Device | OS | Role |
|---|---|---|
| iPhone (current shipping, e.g. 16/17) | iOS 26 | Primary visual + HealthKit + Island |
| iPhone SE-class if still supported on 26 | iOS 26 | Small screen, Capture crowding |
| iPad | iOS 26 | If we still ship iPad layouts — size classes + glass |
| Mac | macOS 26 | Dashboard, not a cloned phone tab bar |
| Simulator iOS 26 | CI | Compile, unit, optional snapshots |

Beta OS: if we start on iOS 26 beta, re-run V1–V10 on **GM** before App Store.

### 5.8 Sign-off

Release is blocked until:

1. Phase A–C shipped (OS floor + chrome).  
2. E2 + E3 (Briefing + Today) visual + V-checks signed.  
3. T-D timeline tests green.  
4. I1–I4 a11y signed on a device.  
5. QA-12 release checklist updated for iOS 26 and completed.

Later E-rows can follow in point releases; chrome + Briefing + Today are the **minimum lovable iOS 26 app**.

---

## 6. Skills to open per phase

| Phase | Read first |
|---|---|
| A–B | `swift-language`, `swift-concurrency`, `swift-testing` |
| C–D | `swiftui-liquid-glass` (+ `references/liquid-glass.md`) |
| E | `swiftui-patterns`, `swiftui-layout-components`, `swiftui-navigation` |
| F | `swiftui-animation`, `swiftui-gestures` |
| G | `widgetkit`, `activitykit`, `app-intents` |
| I | `ios-accessibility` |
| J | `app-store-review`, `app-store-optimization` |

Local clone: `~/.cursor/skills-src/swift-ios-skills/skills/<name>/SKILL.md`.
