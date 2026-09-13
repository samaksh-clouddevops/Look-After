



Investigation-only audit. No production code was modified.

## 1. Executive Summary

- Force-failure inventory (`as!`, `try!`, `fatalError(`, `preconditionFailure(`)
  across all non-test, non-preview Swift files: **4 occurrences**, all
  `fatalError` calls, all in the SQLite store initializers under
  `Packages/LookAfterData/Sources/LookAfterData/Persistence/`.
- Concurrency/continuation audit of all `withCheckedContinuation` /
  `withCheckedThrowingContinuation` call sites (12 across the app/data
  packages): no double-resume, lost-continuation, or logout-race defects
  found — all sites resume exactly once and guard optional continuations
  with `continuation = nil` after use.
- **Confirmed:** 1 root-cause cluster (4 instances) — unrecoverable
  `fatalError` on SQLite store initialization failure.
- **Confirmed (sub-case):** 1 additional trigger of the same cluster via
  corrupted legacy JSON migration in `TaskSQLiteStore`.
- **Confirmed (MEDIUM):** stale captured `userId` in the focus-session
  completion closure survives account switching without app relaunch,
  causing behavior data / Brain refresh to run against the wrong user.
- Critical/High severity confirmed issues: **1 cluster, HIGH-severity**.
- Medium severity confirmed issues: **1** (account-switch stale userId).

## 2. Critical Crashes

None found with certainty of common-flow reachability.

## 3. High-Severity Crashes

### [HIGH] — Unrecoverable `fatalError` on SQLite store open failure

**Category:** Persistence / Startup

**Feature:** Task storage, Inbox, Health summary, Module entities (bills,
shopping, relationships, journal) — all local-first on-device persistence.

**File + Function:**
- `Persistence/TaskSQLiteStore.swift:60` — `init(databaseURL:documentsDirectory:migrateFromJSON:)`
- `Persistence/InboxSQLiteStore.swift:53` — `init(databaseURL:)`
- `Persistence/ModuleEntitySQLiteStore.swift:71` — `init(databaseURL:documentsDirectory:migrateFromJSON:)`
- `Persistence/HealthSummarySQLiteStore.swift:64` — `init(databaseURL:...)`

**Exact Location:** each `catch { fatalError("[...] Failed to open database: \(error)") }`
block wrapping `DatabaseQueue(path:configuration:)` + `createSchema` (+ JSON
migration for Task/ModuleEntity stores).

**Trigger:** `DatabaseQueue` initialization or the wrapped `dbQueue.write`
schema/migration block throws. Realistic causes:
- Device out of disk space when GRDB needs to grow the WAL/journal file.
- SQLite file corrupted by an interrupted write (force-quit, low battery
  power-off, or unexpected termination mid-write on a device without
  atomic file protection guarantees for the WAL).
- Restore-from-backup or iCloud file-provider placeholder producing a file
  the OS reports as present but not yet fully materialized/readable.

**Preconditions:** Any of the above conditions exist for the specific
`.sqlite` file in `Documents/` at the time `XxxSQLiteStore.shared` (a
lazy static `let`) is first accessed — which happens during normal app
bootstrap for all four stores.

**Reproduction:**
```text
1. Corrupt or truncate Documents/tasks.sqlite (e.g., simulate an
   interrupted write by truncating the file mid-page).
2. Launch the app.
3. TaskSQLiteStore.shared is accessed during bootstrap.
4. DatabaseQueue(path:) throws (file is not a valid SQLite database).
5. catch block executes fatalError -> app terminates immediately.
6. Relaunch the app -> same corrupted file is still on disk -> same
   fatalError -> permanent crash loop with no self-repair path.
```

**Execution Path:**
```text
App launch / first store access
→ XxxSQLiteStore.init(databaseURL:...)
→ DatabaseQueue(path:) or dbQueue.write { createSchema/migrate } throws
→ catch { fatalError(...) }
→ process terminates
```

**Expected Behavior:** A corrupted or temporarily inaccessible database
file should not permanently brick the app. At minimum the app should be
able to fall back to an empty/rebuilt store (with logging/telemetry) or
show a recoverable error state, rather than crash on every launch.

**Actual Behavior:** The app crashes immediately and irrecoverably — the
corrupted file is never deleted or worked around, so every subsequent
launch repeats the exact same crash until the user deletes/reinstalls the
app (data loss either way).

**Crash Mechanism:** Explicit `fatalError` call, i.e. a deliberate trap
converting a recoverable `Error` into an unconditional process
termination with no retry/fallback logic.

**User Impact:** Complete, permanent app unusability ("crash loop") for
any affected user until reinstall, which also destroys all local data
across whichever store(s) hit the corrupted file.

**Evidence:**
```text
} catch {
    fatalError("[TaskSQLiteStore] Failed to open database: \(error)")
}
```
(same shape in the other three stores — see file:line list above).

**Confidence:** High (mechanism is unconditional and unconditionally
reachable given file corruption/disk pressure; only the *probability* of
triggering corruption is environment-dependent, not the crash itself).

**Recommended Fix:** On `DatabaseQueue`/schema init failure, attempt one
recovery pass — e.g. move the corrupt file aside (`*.corrupt` backup) and
retry creating a fresh database — before falling back to `fatalError`
only if the retry also fails. Log/report the corruption event instead of
silently losing data.

---

### [MEDIUM] — Same fatalError cluster reachable via corrupted legacy JSON migration (TaskSQLiteStore only)

**Category:** Persistence / Migration

**File + Function:** `TaskSQLiteStore.swift:194` `migrateFromJSONIfNeeded`,
called from `init` inside the same `try dbQueue.write { ... }` block that
feeds the `fatalError` catch at line 60.

**Trigger:** A pre-existing `Documents/tasks.json` from an older app
version is present, non-empty per `FileManager.fileExists`, but contains
truncated/malformed JSON (e.g., previous app instance was killed mid
`FileManager` write of the legacy JSON store, before the SQLite migration
shipped).

**Reproduction:**
```text
1. Simulate an app version prior to the SQLite migration by placing a
   truncated/invalid tasks.json in Documents/.
2. Ensure tasks.sqlite does not yet exist (fresh migration path).
3. Launch the app (upgrade scenario).
4. migrateFromJSONIfNeeded: Data(contentsOf:) succeeds, but
   jsonDecoder.decode([LifeTask].self, from:) throws.
5. Error propagates out of the write block into the same catch → fatalError.
```

**Execution Path:**
```text
Upgrade launch (tasks.sqlite absent, tasks.json present but corrupted)
→ TaskSQLiteStore.init → dbQueue.write { createSchema; migrateFromJSONIfNeeded }
→ JSONDecoder.decode throws
→ catch → fatalError
```

**User Impact:** Users upgrading from a pre-SQLite build with a corrupted
legacy JSON file are permanently locked out on first launch of the new
version — same crash-loop/reinstall consequence as above.

**Confidence:** Medium (requires a specific corrupted legacy file to be
present at upgrade time; not exercised on typical fresh installs, but is
a real one-time upgrade hazard for existing users).

**Recommended Fix:** Wrap the JSON migration specifically in `try?`/`do-catch`
that logs and skips migration (leaving `tasks.json` in place for manual
recovery) rather than letting a decode failure escalate to the same
process-fatal `catch`.

## 4. Medium/Low Stability Issues

### [MEDIUM] — Stale `userId` captured in focus-session-ended closure survives account switch

**Category:** Concurrency / Lifecycle / Account Switching

**Feature:** Focus timer ("Flow session") completion → Brain orchestration.

**File + Function:** `Apps/LookAfter-iOS/Experience/ExperienceRootLifecycleModifier.swift:55-67` `configureOnLaunch()`.

**Exact Location:**
```swift
private func configureOnLaunch() async {
    guard firebase.isAuthenticated else { return }
    let userId = firebase.resolvedUserId
    ...
    shell.adhdVM.onFocusSessionEnded = { minutes, _ in
        Task {
            await shell.brainVM.handleFlowSessionEnded(durationMinutes: minutes, userId: userId)
            shell.refreshWidgetData()
        }
    }
    shell.bootstrap(userId: userId, healthSync: healthSync)
}
```

**Trigger:** `configureOnLaunch()` runs once via `.task` on the initial
authenticated app launch and captures `userId` by value into the
`onFocusSessionEnded` closure. On sign-out → sign-in-as-different-user
within the same app session, `.onChange(of: firebase.isAuthenticated)`
(line 147-161 of the same file) explicitly skips re-running
`configureOnLaunch()` — the code comment says "Launch while already
signed in is handled by `.task` → configureOnLaunch" — and only calls
`shell.bootstrap(userId: firebase.resolvedUserId, ...)` with the new
user's id. The closure itself is never reassigned, so it keeps the old
user's id.

**Preconditions:** User A launches and uses the app (closure captured
with A's id) → signs out → User B signs in on the same running app
instance (no relaunch) → User B starts and completes a focus/flow
session.

**Reproduction:**
```text
1. Sign in as User A; let the app run configureOnLaunch() (first launch).
2. Sign out (firebase.isAuthenticated -> false).
3. Sign in as User B in the same app session.
4. Start a Focus/Flow session as User B and let it end (adhdVM fires
   onFocusSessionEnded).
5. The still-installed closure calls
   shell.brainVM.handleFlowSessionEnded(durationMinutes:, userId: <A's id>).
```

**Execution Path:**
```text
User B ends focus session
→ AdhdViewModel.onFocusSessionEnded(minutes, _) (closure captured at A's launch)
→ BrainViewModel.handleFlowSessionEnded(durationMinutes:, userId: staleUserIdA)
→ FlowDirector.handleFlowSessionEnded → behaviorStore.recordFlowSession(...)
→ BrainViewModel.refresh(userId: staleUserIdA) → taskRepo/healthRepo/energyRepo
  reads scoped to User A's id while User B is the active session
```

**Expected Behavior:** Focus-session completion should always operate on
the currently signed-in user's id.

**Actual Behavior:** Behavior-memory recording and the subsequent Brain
refresh run against the previous user's id, i.e. writes/reads are
attributed to the wrong account.

**Crash Mechanism:** Not a crash — an invalid-state / cross-account data
attribution bug caused by a captured-by-value id in a long-lived closure
that isn't refreshed on re-authentication.

**User Impact:** On shared devices (e.g., family iPad) where users switch
accounts without relaunching the app, one user's focus-session behavior
data/telemetry can be recorded against another user's account, and the
Brain surface can momentarily refresh using the wrong user's task/health
data.

**Evidence:** See code excerpt above; confirmed no other call site
reassigns `shell.adhdVM.onFocusSessionEnded` on re-authentication (only
`shell.bootstrap(userId:)` is called from the sign-in `onChange` handler).

**Confidence:** Medium (requires the specific "switch accounts without
killing the app" flow; common on shared/family devices, not on
single-user devices where sign-out is normally followed by app
termination or the same user re-signing in).

**Recommended Fix:** Re-run `configureOnLaunch()` (or at minimum
reassign `onFocusSessionEnded`) whenever `firebase.isAuthenticated`
transitions from `false` to `true`, not only on first app launch —
mirroring how `shell.bootstrap` is already re-invoked for that
transition.

## 5. Startup / Bootstrap

Covered above (Section 3). No other production-reachable fatal issues
found in bootstrap code (`LookAfterApp.init()` was already reviewed and
fixed for a performance defect in a prior audit; no new crash risk found
there).

## 6–13. Other Categories

Continuation/async-bridge safety, SwiftUI/UIKit lifecycle, general
concurrency races, networking/decoding, AI/streaming, memory pressure,
and cross-feature sequences were spot-checked:

- 12 `withCheckedContinuation`/`withCheckedThrowingContinuation` call
  sites (incl. `AppleSignInCoordinator`, `LocalPersistenceManager`,
  `BehaviorMemoryPersistenceBackend`, `HealthManager`) — all resume
  exactly once with `continuation = nil` guards; no defects.
- AI/GLM streaming and structured-output parsing (`GLMService.stream`,
  `PlanningResponseParser`, `NaturalLanguageTaskCaptureService`,
  `TaskDecomposer`, `DecideForMePicker`) — consistently uses `as?`/`try?`/
  `guard let` with offline/fallback paths on malformed or partial model
  output; no force unwraps found.
- Collection mutation sites (`remove(at:)`/`insert(_:at:)`) in
  `TasksViewModel`, `BrainViewModel`, `TaskCardStackView`,
  `LifeModulesViewModel` — indexes are always recomputed via
  `firstIndex(where:)` immediately before use on the same actor hop; no
  stale-index races found.
- Logout / factory-reset paths (`FirebaseManager.signOut`,
  `FactoryResetManager.performLocalReset`, `AppShellState.clearInMemoryState`)
  — consistently use `try?`/best-effort cleanup, no force unwraps or
  fatal paths.
- Account-switching path (`ExperienceRootLifecycleModifier`) — surfaced
  one confirmed MEDIUM issue (Section 4): a closure capturing a stale
  `userId` across sign-out/sign-in without relaunch.

Given the very narrow force-failure surface area found in Wave 1 (only 4
production `fatalError` sites, 0 production `as!`/`try!`/
`preconditionFailure`), deeper per-file review across the remaining
waves surfaced one additional MEDIUM account-switching issue and no
further confirmed crash paths within this audit pass.

## 14. Root Cause Clusters

**Cluster A — "Unrecoverable persistence-open fatalError"**: shared
pattern in all four SQLite store initializers; single fix pattern (retry
with corrupt-file quarantine before fatalError) would resolve all 4 + the
JSON-migration sub-case in one change.

**Cluster B — "Launch-time closure capture not refreshed on
re-authentication"**: `configureOnLaunch()` wires up
`shell.adhdVM.onFocusSessionEnded` once per process lifetime; any future
per-user closure wired the same way would carry the same defect class.

## 15. Top 20 Crash Risks

1. HIGH — SQLite store open failure → permanent crash loop (Cluster A, 4 sites).
2. MEDIUM — Corrupted legacy `tasks.json` migration → same crash loop (TaskSQLiteStore).
3. MEDIUM — Stale `userId` in focus-session-ended closure → cross-account data
   attribution after in-session account switch (Cluster B).

No further candidates met the confirmation bar in this pass.

## 16. Regression Test Recommendations

- Unit test: initialize `TaskSQLiteStore`/`InboxSQLiteStore`/
  `ModuleEntitySQLiteStore`/`HealthSummarySQLiteStore` with a deliberately
  corrupted (truncated/non-SQLite-magic-bytes) file at the target path;
  assert the store initializes successfully (post-fix) instead of
  crashing, and that the corrupt file is quarantined.
- Unit test: seed `tasks.json` with invalid JSON before constructing
  `TaskSQLiteStore(databaseURL:documentsDirectory:migrateFromJSON: true)`
  pointing at a fresh `tasks.sqlite`; assert init succeeds with an empty
  store (post-fix) rather than crashing.
- Integration test: sign in as User A on a fresh app process, sign out,
  sign in as User B without relaunching, end a focus/flow session as
  User B, and assert `BrainViewModel.handleFlowSessionEnded` /
  `FlowDirector.handleFlowSessionEnded` are invoked with User B's id
  (post-fix), not User A's.

## 17. Coverage Matrix

| Area | Files | Reviewed | Candidates | Confirmed |
| ---- | ----: | -------: | ---------: | --------: |
| Force-failure inventory (repo-wide, non-test/preview) | ~600 (`.swift`, via `git grep`) | Full grep pass | 4 | 4 (1 cluster) |
| Persistence (SQLite stores) | 4 | Full read | 5 (incl. JSON migration sub-case) | 5 |
| Concurrency / continuations | 12 call sites across 9 files | Full read at each site | 0 | 0 |
| AI/GLM streaming & structured-output parsing | 5 (`GLMService`, `PlanningResponseParser`, `NaturalLanguageTaskCaptureService`, `TaskDecomposer`, `DecideForMePicker`) | Full read | 0 | 0 |
| Collection mutation (`remove(at:)`/`insert(_:at:)`) sites | 4 (`TasksViewModel`, `BrainViewModel`, `TaskCardStackView`, `LifeModulesViewModel`) | Full read at each site | 0 | 0 |
| Logout / factory-reset | 3 (`FirebaseManager`, `FactoryResetManager`, `AppShellState`) | Full read | 0 | 0 |
| Account switching / SwiftUI lifecycle | `ExperienceRootLifecycleModifier`, `BrainViewModel`, `FlowDirector` | Full read | 1 | 1 (MEDIUM) |
| Background/notification lifecycle | Spot-checked (`BackgroundAnalyticsScheduler`, `BackgroundNotificationRefreshTask`, `BehavioralTelemetryBackgroundTask`) | Partial | 0 | 0 |
| Networking/decoding, memory pressure | Spot-checked (prior + this session) | Partial | 0 | 0 |

Coverage is **not exhaustive** for background/notification and
networking/memory categories — this pass prioritized the highest-yield
areas (force failures, persistence, continuations, AI parsing,
collection mutation, logout, account switching) per the
"high-confidence, not most issues" directive. Further waves would be
needed to claim full coverage of Sections 6–21 in the original brief.
