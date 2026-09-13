# Performance Bug Hunt Findings (2026-09)

Deep multi-agent performance audit of the Swift/iOS/macOS repository. Goal: find
real, user-impacting performance defects (not theoretical micro-optimizations).
No production code has been modified as part of this audit — findings only.

Status legend: `CONFIRMED` (verified in code, high confidence) · `SUSPECTED`
(needs more evidence) · `FIXED` (patched after being confirmed here).

---

## Wave 1 — Startup / Main Thread / DB / Network

### 1. `FIXED` — Synchronous Keychain + file I/O chain blocked app launch on every cold start

**File:** `Apps/LookAfter-iOS/App/LookAfterApp.swift` (`init()`)
**Also:** `Packages/LookAfterAI/Sources/LookAfterAI/GLM/Providers/GLMKeyManager.swift`

Before:

```swift
init() {
    LookAfterFirebaseConfiguration.configureIfNeeded()
    AuthProxyBootstrap.configureIfNeeded()
    _ = GLMKeyManager.shared.syncDeveloperCredentials()
    _ = GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
    UITestLaunchConfiguration.applyIfNeeded()
}
```

**Fix applied:** the two credential-sync calls (Keychain + filesystem I/O) are
now dispatched via `Task.detached(priority: .utility)` instead of running
inline in `init()`, so `WindowGroup`/`ContentView` no longer wait on them
before rendering the first frame:

```swift
init() {
    LookAfterFirebaseConfiguration.configureIfNeeded()
    AuthProxyBootstrap.configureIfNeeded()
    UITestLaunchConfiguration.applyIfNeeded()
    Task.detached(priority: .utility) {
        _ = GLMKeyManager.shared.syncDeveloperCredentials()
        _ = GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
    }
}
```

`UITestLaunchConfiguration.applyIfNeeded()` was verified independent of the
credential sync (only touches `UserDefaults`/`UserLifeProfileStore`/
`FirebaseManager` session seeding) and was moved ahead of the now-deferred
sync so UI-test bootstrap ordering is unaffected. The credential sync still
runs on every launch (unchanged behavior/timing relative to each other) —
it just no longer blocks time-to-first-frame.

`LookAfterApp.init()` runs on the main thread before `WindowGroup`/`ContentView`
renders (first frame is blocked on this returning). Chain of synchronous work
triggered on **every** cold launch:

- `GLMKeyManager.shared` (lazy static) — `init` calls `loadRecords()`
  (UserDefaults), `migrateLegacyKeysIfNeeded()` and
  `seedBundledDefaultKeyIfNeeded()`, each of which can call
  `secretStore.load`/`save` → Keychain (`SecItemCopyMatching`/`SecItemAdd`),
  which are synchronous IPC round-trips to `securityd`.
- `syncDeveloperCredentials()` — probes up to 3 hardcoded filesystem paths via
  `FileManager.default.isReadableFile(atPath:)`, then does a synchronous
  `String(contentsOf:encoding:)` disk read, then `upsertNamedKey(...)` which
  does another Keychain `load`/`save` round-trip plus `JSONEncoder().encode` +
  `UserDefaults.standard.set` under an `NSLock`.
- `syncOpenAIDeveloperCredentials()` — repeats a similar Keychain
  load/resolve/store chain for the OpenAI key.

Net: 4-6+ chained synchronous Keychain operations plus filesystem stat/read
calls on the main thread before first frame, on every launch (not just first
run). Keychain IPC calls typically cost 5-20ms+ each and can spike higher
right after device boot when `securityd` itself is cold.

**User impact:** slower perceived app launch (time-to-first-frame), worst on
cold boot / low-memory relaunch — exactly when launch speed matters most.

**Suggested fix direction (not applied):** move `syncDeveloperCredentials()` /
`syncOpenAIDeveloperCredentials()` off the launch-blocking path — e.g. run
them in a background `Task` after the first frame is presented, or only run
the file-probe/credentials-sync path in DEBUG builds (it looks like a
developer-convenience credential loader, not something release users need
synchronously at every launch).

---

## Wave 2 — SwiftUI / Tasks / Scheduling / AI

Reviewed: `TaskListView.swift` (filter caching), `TasksViewModel.swift`
(hash-based `taskTimeDisplays` cache, AI auto-fill/time-display refresh),
`GLMService.swift` (chat/completion call sites), `TaskListSorter.swift`,
`TaskScheduleQuery.swift`, `TaskRecurrenceEngine.swift`.

No high-confidence user-impacting defects found yet in this wave:

- `TaskListView.updateFilteredTasksIfNeeded()` builds a content hash by
  mapping+joining a string per task every time `tasksContentRevision`,
  filter, or `editingTask` changes — O(n) string allocation, but it is
  properly guarded (not run on every render) and only triggered on real
  content changes. Not flagged as a defect; would only matter at very large
  (1000+) task counts, which is an edge case, not typical usage.
- `GLMService` chat/completion calls have no cross-call caching, but all call
  sites found so far are user-initiated (auto-fill, AI review, chat) rather
  than fired automatically on render/navigation — acceptable.
- `TaskListSorter.sortForToday` already caches `todayStart` once per sort
  instead of recomputing `Calendar.startOfDay` per comparison — good.

Also checked timer-driven views for main-thread churn:

- `VisualFocusTimer` (`DailyPlanView.swift`) — `Timer.publish(every: 1, ...)`
  drives a simple int decrement; scoped to a single full-screen timer view,
  cancels via `.onDisappear`-adjacent lifecycle. Fine.
- `ADHDViewModel.startFocusTimer()` — 1s `Task.sleep` loop, guarded by
  `isFocusSessionActive`/cancellation, stops itself. Fine.
- `ExecutiveLiveTimelineView` — `TimelineView(.periodic(from: .now, by: 30))`,
  a 30s cadence for a live timeline, reasonable and only active while the
  timeline is on screen.

No high-confidence defect found in Wave 2. Closing this wave.

---

## Wave 3 — Memory / Background / Images / I/O

Checked image loading/decoding and background sync paths:

- No dedicated image cache layer exists in the app (`AsyncImage`/remote image
  usage not found; local previews decode `Data` → `UIImage` directly, e.g.
  `LifeContextFrame`). This is already a known, accepted limitation tracked in
  `Documentation/architecture/mobile-infrastructure-roadmap.md` (item L3) —
  not currently a user-facing defect since the app doesn't load remote/avatar
  images at scale yet. Not re-flagged as a new bug.
- `Repositories.warmLocalCache` explicitly loads `tasks.sqlite` off the main
  thread (`await taskStore.loadAllAsync()`), and `TasksViewModel.loadTasks`
  is structured to hydrate the on-device cache before painting — consistent
  with avoiding main-thread DB I/O at startup for the *task data* path
  (separate from the Keychain/credentials issue in Wave 1, which is a
  distinct init()-time cost).
- `TaskImportSheet.handleFileSelection` reads the imported file synchronously
  via `Data(contentsOf: url)` on the main thread before dispatching parsing
  to a `Task`. This is a user-initiated, one-off file picker action (not a
  frequent/automatic path) and import files are expected to be small
  (task lists), so this is low-impact — noted but not flagged as a
  high-confidence defect.

No high-confidence defect found in Wave 3.

## Wave 4 — Cross-feature / Scale / Verification

**Summary of confirmed, user-impacting performance defects found in this
audit:**

1. `FIXED` — Synchronous Keychain + file I/O chain in `LookAfterApp.init()`
   blocked time-to-first-frame on every cold launch (see Wave 1, finding #1).
   This was the one high-confidence, measurable defect identified with clear
   user impact (slower app launch); it has been patched by deferring the
   credential-sync calls to a detached background task.

All other areas inspected (task list filtering/caching, AI call sites,
scheduling/recurrence engines, timers, image loading, background cache
warm-up) were found to already have appropriate guards (hash-based
invalidation, off-main-thread hydration, cancellation-safe timers) and did
not surface additional high-confidence, user-impacting performance defects
in this pass.

**Coverage note:** this audit focused on startup, task list/scheduling,
AI/GLM call sites, timer-driven views, and image/file I/O. It did not do a
line-by-line pass of every screen (e.g. Home management, Health sync
internals, Brain/executive orchestration engines) — those remain candidates
for a follow-up pass if desired.
