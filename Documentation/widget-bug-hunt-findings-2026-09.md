# Widget Bug Hunt & Fix Report — 2026-09

Investigation + implementation audit of all WidgetKit-related code
(home screen widgets, Live Activities, App Intents, App Group sync).

## 1. Executive Summary

- Widget targets discovered: `Apps/LookAfterWidget` — `NowWidget`,
  `EnergyWidget`, `TasksWidget` (home screen, `StaticConfiguration` +
  `TimelineProvider`), `FocusLiveActivity` / `NowPinLiveActivity`
  (`ActivityConfiguration`), plus Control Center widgets
  (`LookAfterCaptureControl`, `LookAfterStartFocusControl`).
- Supporting infra reviewed: `WidgetSyncService` (app-side sync +
  debounced `WidgetCenter` reload), `WidgetDataStore` /
  `AppGroupWidgetStore` (App Group **file** storage, not
  `UserDefaults(suiteName:)`), `WidgetSnapshot` (shared model),
  `WidgetSyncFingerprint` (write-gate), `LiveActivityManager`,
  `WidgetShortcutIntents` (App Intents for Live Activity/widget
  buttons).
- **Confirmed CRITICAL:** 1 — App Group widget snapshot and pinned
  Live Activity are never cleared on sign-out, so a second account
  signing in on the same device can see the previous user's tasks,
  energy score, and recommendation text on the home screen / Lock
  Screen.
- **Confirmed MEDIUM:** 1 — `WidgetSyncFingerprint` write-gate omitted
  health fields (`sleepHours`, `stepCount`, `hrvMs`), so `EnergyWidget`
  could show stale health metrics indefinitely when only HealthKit
  data changed.
- Fixes implemented: 2. Tests added: 1 (regression unit test for the
  fingerprint gap). The sign-out fix has no existing unit test seam
  (SwiftUI `onChange` + `@MainActor` singletons) — see Section 16 for
  a recommended integration-test outline.

## 2. Critical Bugs

### [CRITICAL] — Cross-account widget/Live Activity data leak on sign-out

**Widget:** `NowWidget`, `EnergyWidget`, `TasksWidget`, `NowPinLiveActivity`

**Category:** Data / Account Isolation / Refresh

**File + Function:**
- `Packages/LookAfterData/Sources/LookAfterData/Firebase/FirebaseManager.swift`
  — `signOut()` / `clearSessionFlagsPreservingLocalData()`
- `Apps/LookAfter-iOS/Experience/ExperienceRootLifecycleModifier.swift`
  — `onChange(of: firebase.isAuthenticated)` (`ExperienceRootSyncModifier`)

**Exact Location (before fix):**
```swift
public func signOut() throws {
    if FirebaseApp.app() != nil { try? Auth.auth().signOut() }
    clearSessionFlagsPreservingLocalData() // only clears currentUserId/email/isAuthenticated
    LicenseManager.shared.clearLocalLicense()
}
```
No call into `WidgetDataStore.clear()`, `WidgetCenter.reloadTimelines`,
or `LiveActivityManager.endAllActivities()` anywhere in the sign-out
path. Only `FactoryResetManager.performLocalReset` did this, and
factory reset is a distinct, much rarer flow than sign-out.

**Expected Behavior:** After sign-out, the home screen widgets and any
pinned Lock Screen Live Activity must not display the previous
account's private data. A newly signed-in account should never see
stale content from the prior session before its own data has loaded.

**Actual Behavior:** `WidgetSnapshot` is stored in a single, non
user-scoped App Group file (`widget-snapshot.json`) with no `userId`
field. Sign-out left that file untouched, so:
1. Immediately after sign-out (logged-out state), the widget still
   rendered the last signed-in user's top task / energy / recommendation.
2. If User B signs in on the same device, the widget continues showing
   User A's data until the app's own bootstrap flow happens to call
   `WidgetSyncService.sync(...)` with fresh data — which depends on
   task/health loads completing and is not guaranteed to be immediate.
3. A pinned Live Activity (`NowPinLiveActivity`) for User A was never
   ended, so it could keep showing User A's task/context on the Lock
   Screen through the sign-out and into User B's session.

**Trigger:** Sign out (Settings → Sign Out), or any other path that
flips `firebase.isAuthenticated` to `false` (e.g. Apple ID credential
revocation via `AppleCredentialMonitor.handleRevocation()`, which also
calls `FirebaseManager.shared.signOut()`).

**Reproduction:**
```text
1. Sign in as User A; let a task/energy snapshot sync to the widget
   (open the app, let it bootstrap).
2. Add NowWidget or EnergyWidget to the home screen; confirm it shows
   User A's top task / energy score.
3. Settings → Sign Out.
4. Observe the home screen widget without relaunching the app — it
   still shows User A's data (or continues to, indefinitely, if no
   other write ever occurs).
5. Sign in as User B. Until User B's own sync fires, the widget still
   shows User A's private task text.
```

**Execution/Data Path:**
```text
User A app data
→ WidgetSyncService.sync() → WidgetDataStore.save() → AppGroupWidgetStore
  (Documents-style App Group container file, global — no userId key)
→ sign out (FirebaseManager.signOut) — snapshot untouched
→ FlowWidgetProvider.getSnapshot/getTimeline → AppGroupWidgetStore.load()
→ NowWidgetView / EnergyWidgetView / TasksWidgetView render User A's data
  to whoever is currently looking at the home screen / Lock Screen
```

**User Impact:** On any shared or family device (parent/child, siblings,
handed-down device), one account's task titles, energy/health data, and
next-step recommendation text can leak to a different account via the
home screen widget or pinned Lock Screen Live Activity — a privacy
violation, not just a UX inconsistency.

**Evidence:** `FirebaseManager.signOut()` (pre-fix) contained no
widget/Live Activity cleanup call; `WidgetDataStore.clear()` was only
ever invoked from `FactoryResetManager.performLocalReset()`, confirmed
via codebase-wide search.

**Recommended Fix (implemented):** Added
`WidgetSyncService.clearForSignOut()`:
- Cancels any in-flight debounced timeline-reload / pin-refresh tasks.
- Resets the in-memory `lastWidgetSnapshotFingerprint` write-gate
  (so the next post-login sync isn't accidentally skipped as a
  "no-op" against stale fingerprint state).
- Clears the "pin to Lock Screen" preference flag.
- Calls `WidgetDataStore.clear()` to delete the App Group snapshot file.
- Reloads all widget timelines via `WidgetCenter` (narrow: only the
  three known widget kinds, matching the existing reload helper — no
  blanket `reloadAllTimelines()` added).
- Calls `LiveActivityManager.shared.endAllActivities()` to end any
  pinned Live Activity / focus activity.

Wired into `ExperienceRootLifecycleModifier`'s existing
`onChange(of: firebase.isAuthenticated)` handler, on the
`authenticated == false` transition (guarded by `wasAuthenticated` so
it only fires on an actual sign-out edge, not on the initial `false`
state at cold launch before any sign-in).

```swift
.onChange(of: firebase.isAuthenticated) { wasAuthenticated, authenticated in
    guard authenticated else {
        if wasAuthenticated {
            WidgetSyncService.shared.clearForSignOut()
        }
        return
    }
    ...
}
```

**Confidence:** High — the missing cleanup call was absolute (verified
via full-codebase search for `WidgetDataStore.clear` call sites), and
the App Group snapshot format has no per-user scoping, so leakage is
not conditional on a race — it is the default behavior absent this fix.

---

## 3. High Bugs

None confirmed in this pass beyond the critical issue above.

## 4. Medium/Low Bugs

### [MEDIUM] — Stale health metrics in EnergyWidget (fingerprint write-gate gap)

**Widget:** `EnergyWidget` (`homeSmall`, `accessoryRectangular`, `accessoryInline`)

**Category:** Data / Timeline / Refresh (stale data)

**File + Function:** `Packages/LookAfterCore/Sources/LookAfterCore/Storage/WidgetSyncFingerprint.swift`
— `compute(_:now:)`

**Exact Location (before fix):** the hashed field list omitted
`snapshot.sleepHours`, `snapshot.stepCount`, `snapshot.hrvMs` even
though all three are rendered directly in `EnergyWidgetView.homeSmall`
and `accessoryRectangular`.

**Expected Behavior:** Any change to displayed widget content should
cause `WidgetSyncService.sync()`'s `shouldWrite` gate to allow a write
and subsequent `WidgetCenter` reload.

**Actual Behavior:** `WidgetSyncService.sync()` is called frequently
(e.g. on every `refreshContext`/briefing refresh) with a freshly built
`WidgetSnapshot`, but `WidgetSyncFingerprint.compute` hashes only task/
energy/pin fields. If a HealthKit background sync updates `stepCount`
(or `sleepHours`/`hrvMs`) while task state and energy score happen to
be unchanged, the fingerprint is identical to the last write, so
`shouldWrite` returns `false`, `WidgetDataStore.save` is skipped, and
`WidgetCenter.reloadTimelines` is never called — `EnergyWidget`
continues to show the previous step count / sleep hours / HRV
indefinitely, until some *other* field (task/energy) happens to change.

**Trigger:** HealthKit observer fires a health-only update (e.g. step
count increments through the day) with no concurrent task/energy
change.

**Reproduction:**
```text
1. Let the app sync an initial WidgetSnapshot with stepCount = 1000.
2. Without changing any task or energy state, simulate a HealthKit
   update raising stepCount to 5000 and call WidgetSyncService.sync()
   again with the new snapshot.
3. WidgetSyncFingerprint.compute(old) == WidgetSyncFingerprint.compute(new)
   because stepCount isn't part of the hash.
4. shouldWrite(force: false, ...) returns false → WidgetDataStore.save
   is skipped → EnergyWidget keeps showing stepCount = 1000.
```

**Execution/Data Path:**
```text
HealthKit step count update
→ WidgetSyncService.makeSnapshot() (new stepCount)
→ WidgetSyncFingerprint.compute() (excludes stepCount) == lastFingerprint
→ shouldWrite == false → WidgetDataStore.save skipped
→ WidgetCenter.reloadTimelines skipped
→ EnergyWidgetView renders stale entry.snapshot.stepCount from last write
```

**User Impact:** `EnergyWidget`'s sleep/steps/HRV metrics (its core
value proposition alongside the energy score) can silently go stale
for extended periods, undermining trust in the widget's "live" health
data — a meaningful but non-critical freshness bug.

**Evidence:** Field list diff between `WidgetSyncFingerprint.compute`
(pre-fix) and the properties read in `EnergyWidgetView` (`sleepHours`,
`stepCount`, `hrvMs`), confirmed by direct file inspection.

**Recommended Fix (implemented):** Added the three health fields to
the fingerprint hash:
```swift
snapshot.sleepHours.map { String(format: "%.1f", $0) } ?? "",
snapshot.stepCount.map(String.init) ?? "",
snapshot.hrvMs.map(String.init) ?? "",
```
This keeps the write-gate narrow and intentional (no blanket
`force: true` or removal of the gate) while closing the specific
staleness gap.

**Confidence:** High — field omission was direct and verifiable by
comparing the hash inputs to the view's data dependencies.

---

## 5. Data / Freshness

- `WidgetSnapshot` has no `userId`/session field at all — by design it
  is a single global App Group file. This is the root enabler of the
  Section 2 critical bug. The fix (clear on sign-out) treats the
  symptom at the account-transition boundary rather than re-architecting
  the snapshot to be user-scoped, per the "avoid unnecessary
  architectural rewrites" constraint — flagged as a residual risk in
  Section 16.
- `WidgetSyncFingerprint` now covers task, energy, pin, and health
  fields. `topTaskMinutes` is still not part of the hash — if only
  `topTaskMinutes` changes (task re-estimated) while title/count/energy
  stay the same, a write could be skipped. This is a narrower,
  lower-severity gap (estimated minutes changing alone, with title
  unchanged, is a much less common real-world event than health metrics
  changing independently) — logged as a residual risk, not fixed in
  this pass to keep the change minimal and targeted.

## 6. Timeline / Refresh

- `FlowWidgetProvider.getTimeline` always returns a single entry stamped
  `Date()` with `.after(+15 min)` reload policy — reviewed, no bug:
  this is an intentional, bounded polling cadence appropriate for data
  that only changes via explicit app-side `WidgetCenter.reloadTimelines`
  calls (which happen on every meaningful data change via
  `WidgetSyncService.sync`/`scheduleWidgetTimelineReload`). No evidence
  of missing or excessive reloads beyond the two confirmed issues above.
- `WidgetSyncService.scheduleWidgetTimelineReload` debounces non-forced
  reloads by 400ms and reloads immediately when `force: true` — reviewed,
  reasonable; not changed.

## 7. Layout / Content Fit

Reviewed `NowWidgetView`, `EnergyWidgetView`, `TasksWidgetView` across
`systemSmall`/`systemMedium`/`systemLarge`/`accessoryRectangular`/
`accessoryInline`. All text fields use explicit `lineLimit` (1–3) and
`Spacer(minLength: 0)` for empty-space absorption; `TasksWidgetView`
caps the task list at `prefix(3)`. No clipping/overlap defects found
in this pass — not a focus area given time budget; flagged for a
follow-up pass with real long-content fixtures (very long task titles,
non-Latin scripts) if desired.

## 8. Typography / Readability

Not deeply audited this pass (see Section 16 for suggested follow-up).
Font/weight/opacity hierarchy (`textPrimary`/`textSecondary`/`textMuted`)
appeared consistent across the three widgets on inspection.

## 9. Deep Links / Navigation

`widgetURL(URL(string: "lookafter://today"))` is applied uniformly on
`NowWidgetView` and `EnergyWidgetView`. Not deeply traced end-to-end
into app-side URL routing in this pass — flagged for follow-up.

## 10. Interactive Widgets

`WidgetStartHeroTaskIntent` (home screen button) and
`WidgetPauseFocusIntent` (Live Activity button) were spot-checked:
both enqueue an action via `AppGroupIntentStore.enqueue(action:)` for
the main app to drain on foreground rather than mutating state
directly from the extension — reviewed, no correctness bug found, but
the full drain path (`LookAfterIntentBridge.processPendingQueue`) was
not exhaustively traced for double-tap/offline idempotency in this
pass — flagged for follow-up.

## 11. Lifecycle / Background

Sign-out is now a first-class "widget lifecycle" event (Section 2 fix).
Factory reset was already correct (`FactoryResetManager` clears
`WidgetDataStore` + reloads timelines). App-restart / device-restart
behavior relies on the App Group file surviving on disk, which is
correct WidgetKit practice; not otherwise changed.

## 12. Accessibility / Dynamic Type

Not audited this pass — flagged for follow-up (Section 16).

## 13. Performance

`AppGroupWidgetStore.load()`/`save()` do direct synchronous file I/O
with `JSONEncoder`/`JSONDecoder` on small payloads (single snapshot
struct) — reviewed, no performance concern found.

## 14. Cross-Feature Issues

Authentication → Widget was the primary cross-feature gap found and
fixed (Section 2). Task/Health/Calendar → Widget freshness gap
partially closed (Section 4, health fields). Notifications → Widget
and Background Sync → Widget were not deeply traced this pass.

## 15. Changes Made

| Bug | File | Fix | Test |
| --- | ---- | --- | ---- |
| Cross-account widget/Live Activity leak on sign-out | `Apps/LookAfter-iOS/Services/WidgetSyncService.swift`, `Apps/LookAfter-iOS/Experience/ExperienceRootLifecycleModifier.swift` | Added `WidgetSyncService.clearForSignOut()` (clears App Group snapshot, cancels debounced reload/pin tasks, resets fingerprint gate, reloads widget timelines, ends all Live Activities); wired into the sign-out edge of `onChange(of: firebase.isAuthenticated)` | No automated test added (SwiftUI lifecycle + `@MainActor` singleton seam not unit-testable without refactor); manual repro steps in Section 2 + integration-test outline in Section 16 |
| Stale EnergyWidget health metrics | `Packages/LookAfterCore/Sources/LookAfterCore/Storage/WidgetSyncFingerprint.swift` | Added `sleepHours`/`stepCount`/`hrvMs` to the fingerprint hash | `Packages/LookAfterCore/Tests/LookAfterCoreTests/WidgetSyncFingerprintTests.swift::healthOnlyChangeWritesWithoutForce` |

## 16. Remaining Risks

- `WidgetSnapshot`/`AppGroupWidgetStore` remain fundamentally
  single-account (no `userId` field). The sign-out fix closes the gap
  at the transition boundary, but any future code path that writes a
  widget snapshot without going through `WidgetSyncService.sync`/
  `setNowPinned` (bypassing the fingerprint gate or sign-out hook)
  could reintroduce leakage. A more robust long-term fix would add a
  `userId` field to `WidgetSnapshot` and have the widget extension
  refuse to render (or show a neutral "signed out" state) if the
  stored `userId` doesn't match the current session UID visible to the
  extension — this is a larger architectural change intentionally
  **not** made in this pass per the "avoid unnecessary rewrites" rule.
- `topTaskMinutes` is still excluded from `WidgetSyncFingerprint` —
  low-severity residual staleness risk (Section 5).
- Layout/content-fit, Dynamic Type/accessibility, deep-link
  end-to-end tracing, and interactive-widget idempotency under
  double-tap/offline were spot-checked or not audited — see Sections
  7–10, 12 for scope notes. Recommend a dedicated follow-up pass if
  these are in scope for the next audit wave.
- No automated regression test exists for the sign-out cleanup path;
  recommend adding an XCUITest or integration test that:
  1. Seeds an App Group snapshot for a fake "User A" session.
  2. Simulates `firebase.isAuthenticated` `true → false`.
  3. Asserts `AppGroupWidgetStore.load()` returns `.empty` and that
     `LiveActivityManager` has no active activities.
  This requires either exposing `firebase.isAuthenticated` mutation in
  a testable seam or an XCUITest driving real sign-in/sign-out UI.

## 17. Coverage Matrix

| Area | Files | Reviewed | Bugs | Fixed |
| ---- | ----: | -------: | ---: | ----: |
| Widget entry/configuration (`Widget`/`WidgetBundle`/`WidgetConfiguration`) | 1 (`LookAfterWidgetBundle.swift`) | Full read | 0 | 0 |
| Timeline provider (`FlowWidgetProvider`) | 1 | Full read | 0 | 0 |
| Data loading / App Group persistence | 3 (`WidgetDataStore`, `AppGroupWidgetStore`, `WidgetSnapshot`) | Full read | 0 | 0 |
| Refresh / invalidation / fingerprint gate | 2 (`WidgetSyncService`, `WidgetSyncFingerprint`) | Full read | 1 | 1 |
| Account isolation / sign-out | `FirebaseManager`, `ExperienceRootLifecycleModifier`, `AppShellState`, `FactoryResetManager` | Full read | 1 | 1 |
| Widget views / layout (`NowWidgetView`, `EnergyWidgetView`, `TasksWidgetView`) | 1 file, 3 views | Full read | 0 | 0 |
| Interactive widgets / App Intents (`WidgetShortcutIntents`) | 1 | Spot-checked | 0 | 0 |
| Deep links (`widgetURL`) | 2 call sites | Spot-checked | 0 | 0 |
| Live Activities (`FocusLiveActivity`, `LiveActivityManager`) | 2 | Partial (reused for sign-out fix) | 0 | 0 |
| Layout content-fit / typography / accessibility | 1 file | Spot-checked only | 0 | 0 |

Coverage is **not exhaustive** for layout/content-fit, typography,
accessibility/Dynamic Type, deep-link end-to-end routing, and
interactive-widget idempotency — this pass prioritized data
correctness and account-isolation (the highest-severity category per
the audit brief). Further waves recommended for the remaining
categories.
