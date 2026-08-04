# Focus Timer UI Lag — Known Issue

**Document ID:** QA-FOCUS-TIMER-LAG  
**Status:** Mitigated on `performance/ui-lag-fixes` — verify on device
**Last updated:** 2026-08-04
**Related:** Today tab, timeline Start now, `FocusSessionView`, `ADHDViewModel`

---

## Summary

Users report that starting a focus session from **Today / timeline** feels broken in two ways:

1. **Visual timer slow to appear** — the countdown/timer runs in the background, but the focus clock UI can take a long time (reported up to ~1 minute) before it shows on screen.
2. **Wrong duration for long blocks** — a task displayed as a 9-hour block (e.g. 8:30 AM – 5:30 PM) was starting a **45-minute** timer instead of matching the scheduled window.

Pause and stop responsiveness were also flagged as worth checking.

---

## Expected behavior

| Action | Expected |
|--------|----------|
| Tap **Start now** on timeline | Focus overlay appears **immediately** (same frame or next frame) |
| Timer duration | Matches **scheduled window** when task has fixed start/end times; otherwise `estimatedMinutes`; otherwise user default |
| Pause | Label switches to **paused** instantly; timer tick stops |
| Stop | Overlay dismisses instantly; user returns to the same tab they were on |

---

## Reported vs actual (suspected root causes)

### 1. UI appears late while timer already runs

**Symptom:** Backend/timer state updates before SwiftUI paints the overlay.

**Likely contributors (investigated, partially mitigated):**

| Cause | Location | Notes |
|-------|----------|-------|
| **ActivityKit blocking main thread** | `LiveActivityManager.startFocusActivity` → `Activity.request(...)` | Synchronous call on focus start can block UI for seconds on device/simulator |
| **`fullScreenCover` presentation delay** | `LookAfterMasterCanvas` | Was switched to `fullScreenCover`; reverted to **ZStack overlay** for faster paint |
| **Live Activity sync on every focus state change** | `ExperienceRootView.onChange` → `WidgetSyncService` | Multiple `onChange` handlers fire on start; now deferred with `Task.yield()` |
| **Timer started before UI render** | `ADHDViewModel.startFocusSession` | Timer tick deferred one run-loop tick; uses `Task`-based tick instead of `Timer` |
| **Heavy first paint** | `FocusSessionView` | Was using `PremiumBackground`; switched to flat `DesignSystem.backgroundPrimary` |
| **Pause resume persistence** | `ExperienceRootView` → `ResumeEngine.captureFocusSession` | UserDefaults write on pause; now deferred |
| **Stop callback before dismiss** | `ADHDViewModel.endFocusSession` → `onFocusSessionEnded` | Brain refresh deferred so `isFocusSessionActive = false` dismisses overlay first |

**Still needs verification on a physical device** — simulator UI tests were flaky; user-reported ~1 min lag may be device-specific or tied to Live Activity + Health sync during bootstrap.

### 2. 9h job → 45 min timer

**Root cause:** `startFocusSession` used `task.estimatedMinutes` (45) while the **timeline** displays duration from `TaskScheduleInterval.window` (540 min for 8:30–5:30).

**Fix applied:** `ADHDViewModel.focusDuration(for:defaultMinutes:)` now prefers scheduled window length, matching `LifeTimelinePresenter` logic.

**Example:** Office task with `estimatedMinutes: 45`, `scheduledEndTime` 5:30 PM → focus session target **540 minutes** (displayed as `9:00:00`).

---

## Code changes already made (2026-08-04)

### ViewModel & duration

- `Packages/LookAfterFeatures/.../ADHDViewModel.swift`
  - `focusDuration(for:defaultMinutes:)` uses `TaskScheduleInterval.window`
  - `Task`-based focus tick (replaces double-registered `Timer`)
  - Deferred timer start after `isFocusSessionActive = true`
  - Deferred `onFocusSessionEnded` callback on stop
  - `focusRemainingString` shows `H:MM:SS` for sessions over 1 hour

### UI shell

- `Apps/LookAfter-iOS/Views/LookAfterMasterCanvas.swift` — ZStack overlay at `zIndex(99)`, not `fullScreenCover`
- `Apps/LookAfter-iOS/Views/ADHD/ADHDViews.swift` — lighter background; accessibility IDs for tests

### Live Activity / widgets

- `Apps/LookAfter-iOS/Services/LiveActivityManager.swift` — `Activity.request` wrapped in deferred `Task`
- `Apps/LookAfter-iOS/Services/WidgetSyncService.swift` — all focus sync deferred; `-SkipLiveActivity` for tests
- `Apps/LookAfter-iOS/Experience/ExperienceRootView.swift` — deferred `onChange` handlers; deferred pause capture

### Timeline / Today

- Skip 3-2-1 countdown for timeline start (`instant: true`)
- Stop returns to same tab via `tabBeforeFocus`

---

## Tests added

### Unit tests (passing)

**File:** `Packages/LookAfterFeatures/Tests/.../ADHDViewModelFocusSessionTests.swift`

| Test | Threshold |
|------|-----------|
| `testStartFocusSessionActivatesWithinOneFrame` | < 50ms |
| `testPauseFocusSessionWithinOneFrame` | < 50ms |
| `testResumeFocusSessionWithinOneFrame` | < 50ms |
| `testEndFocusSessionWithinOneFrame` | < 50ms |
| `testFocusDurationUsesScheduledWindowForLongWorkBlock` | 540 min |
| `testFocusDurationFallsBackToEstimateWhenNoScheduleWindow` | 45 min |

```bash
cd Packages/LookAfterFeatures && swift test --filter ADHDViewModelFocusSessionTests
```

### UI performance tests (added, not reliably green yet)

**File:** `Apps/LookAfterUITests/Performance/FocusTimerOpenPerformanceTests.swift`

| Test | Measures | Target / hard fail |
|------|----------|-------------------|
| `testFocusTimerOverlayAppearsQuicklyOnAutoStart` | Bootstrap → overlay visible | 100ms / 500ms |
| `testFocusTimerOpensInstantlyFromTodayTimeline` | Start now → timer visible | 100ms / 500ms |
| `testFocusTimerTapOpenLatencyStableAcrossRuns` | Average of 4 tap runs | 100ms / 500ms |
| `testPauseUpdatesTimerLabelInstantly` | Pause → "paused" label | 100ms / 500ms |
| `testStopDismissesFocusScreenInstantly` | Stop → overlay gone | 100ms / 500ms |
| `testResumeAfterPauseWithinThreshold` | Resume → "remaining" label | 100ms / 500ms |

**UITest launch flags:**

| Flag | Purpose |
|------|---------|
| `-UITesting` | Enables test configuration |
| `-SkipLiveActivity` | Skips ActivityKit (also disables health sync in config) |
| `-AutoStartFocusSession` | Starts focus after bootstrap completes |
| `-SeedFocusTask` | Seeds `timeline-event-card-uitest-focus-task` on Today |

**Accessibility IDs:** `screen-focus-session`, `focus-timer-remaining`, `focus-timer-status`, `focus-start-now`, `focus-session-pause-toggle`, `focus-session-stop`, `timeline-event-card-{taskId}`

### UI test failures observed (2026-08-04)

- Simulator **preflight / busy** errors when not booted cleanly
- All 6 UI tests failed when auto-start ran **before** bootstrap finished
- Fixes attempted: sync Firebase auth in `UITestLaunchConfiguration`, move auto-start to **end of** `AppShellState.bootstrap` Task, disable health sync when `-SkipLiveActivity`

**Re-run command:**

```bash
xcrun simctl boot <iPhone-17-UDID>
cd Look-After && xcodebuild test -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,id=4AA438FD-477F-4023-92A6-362311914C76' \
  -only-testing:LookAfterUITests/FocusTimerOpenPerformanceTests
```

Evidence JSON written to `Documentation/qa/.engine/evidence/PERF-FOCUS-TIMER-*.json` when tests run.

---

## Follow-up checklist

### Must verify on device

- [ ] Tap **Start now** on a real 9h fixed block — confirm timer shows **9:00:00** (not 45:00)
- [ ] Measure tap → overlay visible with Instruments Time Profiler + os_signpost
- [ ] Test with Live Activities **enabled** (production path) vs disabled
- [ ] Test on low-end device and with Low Power Mode

### If lag persists

1. **Profile main thread** during `startFocusSession` — look for `Activity.request`, Health sync, Firebase, brain orchestration
2. Consider **lazy Live Activity** — start only after overlay has been visible for 1–2 seconds
3. Consider **`@MainActor` signposts** around focus start/pause/stop for CI regression
4. Audit **`ExperienceRootView.onChange`** chain — multiple handlers still fire on focus start (`isFocusSessionActive`, `focusSessionTarget`, etc.)
5. Confirm **no duplicate overlay** or auth `fullScreenCover` competing with focus ZStack

### UI tests to stabilize

- [ ] Green all `FocusTimerOpenPerformanceTests` on CI simulator
- [ ] Add `-PerfTesting` flag that skips health, brain orchestration, and Live Activity in one place
- [ ] Wait for bootstrap-complete signal before auto-start assertions (accessibility marker e.g. `uitest-bootstrap-complete`)

### Related files

| File | Role |
|------|------|
| `ADHDViewModel.swift` | Focus state, duration, timer tick |
| `LookAfterMasterCanvas.swift` | Focus overlay placement |
| `FocusSessionView` in `ADHDViews.swift` | Timer UI |
| `ExecutiveLiveTimelineView.swift` | Start now button |
| `LiveActivityManager.swift` | Lock Screen / Dynamic Island |
| `ExperienceRootView.swift` | Focus lifecycle hooks |
| `AppShellState.swift` | Bootstrap, UITest seed/auto-start |
| `UITestLaunchConfiguration.swift` | Test launch args |

---

## Performance targets (from QA-09)

| Metric | Target | Hard fail |
|--------|--------|-----------|
| Focus timer open (tap → visible) | < 100ms | > 500ms |
| Pause / resume label update | < 100ms | > 500ms |
| Stop → dismiss overlay | < 100ms | > 500ms |
| ViewModel state flip (start/pause/stop) | < 16ms | > 50ms |

See also: [09-performance-benchmarks.md](./09-performance-benchmarks.md)

---

## Conversation context

Work originated from Today/timeline polish: skip countdown, use task duration, fix slow focus clock. User confirmed lag persisted after initial Live Activity deferral. Duration bug (9h → 45m) was a separate logic issue in `focusDuration` vs timeline display.

**Priority when resuming:** Confirm fix on **physical device** first; unit tests pass but do not validate SwiftUI paint time or ActivityKit blocking.
