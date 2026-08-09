# Application Bug Audit Report

**Document ID:** QA-BUG-AUDIT
**Date:** 2026-08-09
**Scope:** Static analysis of iOS/macOS Swift codebase (Apps + Packages)
**Method:** Architecture review, concurrency/memory scan, known-risk cross-check against QA docs
**Status:** Remediation on branch `fix/bug-audit-remediation` — P0 + key P1 fixed in code

---

## Executive summary

| Severity | Count | Fixed on branch | Remaining |
|----------|------:|:---------------:|----------:|
| **Critical (P0)** | 6 | 6 | 0 |
| **High (P1)** | 9 | 7 | 2 (device lag verify; planning choke-point audit) |
| **Medium (P2)** | 12 | 6 | 6 |
| **Low (P3)** | 8 | 0 | 8 |
| **Brain / decision** | 3 open (existing log) | 0 | Ship gate per QA-14 |

**Remediation branch:** `fix/bug-audit-remediation` (one commit per fix cluster).

**Still open for ship quality:** BUG-007 device focus-lag verification, BUG-014 full planning-apply choke-point audit, brain issues #12 / #L-003.

---

## How to read each bug

| Field | Meaning |
|-------|---------|
| **Layer** | View / ViewModel / Service / Data / Auth / Brain / Widget |
| **Impact** | User-visible consequence |
| **RCA** | Root cause (Swift-specific notes) |
| **Fix sketch** | Targeted direction (not applied here) |
| **Safety** | Thread / memory notes |
| **Tests** | Suggested coverage |
| **Related** | Risk IDs / existing QA docs |

---

## P0 — Critical

### BUG-001 — Optimistic email/anonymous auth ignores Firebase failure

| | |
|--|--|
| **Layer** | Auth (`FirebaseManager`) |
| **Files** | `Packages/LookAfterData/.../Firebase/FirebaseManager.swift` (~L88–166) |
| **Impact** | Wrong password / network failure still marks user authenticated with synthetic `usr_*` / `guest_*` UID. Tasks, license, and cloud sync attach to a non-Firebase identity until (if ever) a later auth listener reassigns data. Silent login failure. |

**RCA:** `signIn`, `createAccount`, and `signInAnonymously` set `isAuthenticated = true` and `currentUserId` **before** Firebase completes, then launch `Task.detached { try? await Auth... }` and discard errors.

**Fix sketch:** Await Firebase auth on the main path; only flip `isAuthenticated` on success; surface errors; keep a single “pending auth” state for offline guest if product requires it. Do not use `try?` on credential auth.

**Safety:** Resolves cross-user data reassignment races when UID flips after bootstrap started under fallback ID (R-004).

**Tests:** Unit: invalid password → `isAuthenticated == false`; success path reassigns only after UID confirmed. UI: FLOW-001 cold launch.

**Related:** R-004, EDGE-N01

---

### BUG-002 — Auth state listener never handles sign-out / nil user

| | |
|--|--|
| **Layer** | Auth |
| **Files** | `FirebaseManager.swift` `setupAuthListener` (~L58–74) |
| **Impact** | Token revoke, remote session end, or `signOut` race can leave UI “signed in” with stale UID while Firestore rejects writes. |

**RCA:** Listener only handles `if let user = user`; no `else` branch to clear `currentUserId` / `isAuthenticated`.

**Fix sketch:**

```swift
if let user {
  // existing apply path
} else {
  currentUserId = nil
  isAuthenticated = false
  // optional: keep local cache UID only if product wants offline guest
}
```

**Safety:** MainActor already; ensure bootstrap cancels when auth drops.

**Tests:** Simulate auth nil after signed-in; assert shell shows Auth and stops cloud writes.

---

### BUG-003 — FlowDirector orchestration is not serialized

| | |
|--|--|
| **Layer** | AI / Brain orchestration |
| **Files** | `Packages/LookAfterAI/.../Flow/FlowDirector.swift` `orchestrate(session:)` (~L77–127) |
| **Impact** | Complete + defer + timer refresh can interleave. Later completion with older `session.pendingTasks` overwrites `surface` → **stale hero** after complete/defer (highest product risk). |

**RCA:** `isOrchestrating` is set/cleared but never used as a mutex. Concurrent `await` pipelines both assign `@Published surface`. Classic lost-update / last-writer-wins. Risk register already rates this RPN 20 (R-001).

**Fix sketch:** Single serial queue / actor token:

```swift
private var orchestrationTail: Task<Void, Never>?

func orchestrate() async {
  let previous = orchestrationTail
  let task = Task { @MainActor in
    await previous?.value
    await self.runOrchestrationPipeline()
  }
  orchestrationTail = task
  await task.value
}
```

Optionally cancel superseded runs and only publish if `generation == latest`.

**Safety:** Keeps `@MainActor`; avoids data races on `surface` / `lastEnvironmentContext`.

**Tests:** LO-IOS-FN-001, FLOW-002, EDGE-B03 — parallel complete+orchestrate → hero matches completed task list.

**Related:** R-001, EDGE-B03

---

### BUG-004 — SQLite task write failures are silent (possible data loss)

| | |
|--|--|
| **Layer** | Data / Persistence |
| **Files** | `Packages/LookAfterData/.../Persistence/TaskSQLiteStore.swift` `replaceAllAsync` / `replaceAllAwait` (~L85–107) |
| **Impact** | Full replace failures only `print`. UI stays optimistic (TasksViewModel already inserted task). Kill app → task gone. Storage-full scenarios uncommunicated (EDGE-V09). |

**RCA:** Fire-and-forget `Task.detached` + swallowed errors. No callback to TaskRepository / UI.

**Fix sketch:** Prefer `replaceAllAwait` on mutation paths; propagate `throws`; mark dirty/outbox for retry; surface `TasksViewModel.error` on failure (already partially exists on create catch — ensure disk path throws).

**Safety:** Detached tasks are fine if errors are observed; avoid unbounded detached chains.

**Tests:** Mock full disk / failing DatabaseQueue → UI rollback + error; LO-DATA-FN-016.

**Related:** R-010, EDGE-V09, EDGE-D04

---

### BUG-005 — `TaskSQLiteStore` init uses `fatalError` on open failure

| | |
|--|--|
| **Layer** | Data |
| **Files** | `TaskSQLiteStore.swift` (~L59–61) |
| **Impact** | Corrupt DB / permission / disk failure → **hard crash** on launch for every session until reinstall. |

**RCA:** `fatalError` in production init path.

**Fix sketch:** Throw / fallback to recovery mode: move corrupt file aside, open empty store, show non-blocking banner, log metric. Never crash cold start for recoverable I/O.

**Tests:** Point store at unwritable path in unit test — no process abort; recovery invoked.

**Related:** EDGE-D04

---

### BUG-006 — Offline capture drain drops items even when routing fails

| | |
|--|--|
| **Layer** | Capture / Data |
| **Files** | `Packages/LookAfterFeatures/.../Capture/CaptureOfflineQueue.swift` `processPending` (~L71–86) |
| **Impact** | On reconnect, every queued capture is removed after `route(...)` **regardless of success**. Failed GLM/network route → user speech/text lost permanently. |

**RCA:** Loop always `remaining.removeAll { $0.id == record.id }` with no result check. Also no queue cap (R-028).

**Fix sketch:** Remove only on `.success` / terminal user-cancel; retain + backoff on failure; cap queue (e.g. 100) with user-visible overflow.

**Tests:** Enqueue 3; force route failure → count remains 3; success drains; LO-DATA-FN related offline cases.

**Related:** R-028, EDGE-N02, FLOW-003

---

## P1 — High

### BUG-007 — Focus timer UI lag not verified on device (partially mitigated)

| | |
|--|--|
| **Layer** | View / Widget / ViewModel |
| **Files** | `ADHDViewModel.swift`, `LiveActivityManager.swift`, `ExperienceRootView.swift`, `LookAfterRootCanvas.swift` |
| **Impact** | Users reported up to ~1 min delay before focus clock UI appears while timer already runs. Pause/stop feel laggy when ActivityKit blocks. |
| **Status** | Mitigations landed; **physical device verification still open**. UI perf tests not reliably green. |

**RCA:** Synchronous ActivityKit + multiple `onChange` → WidgetSync; heavy first paint; bootstrap races with auto-start. Documented in [focus-timer-ui-lag.md](focus-timer-ui-lag.md).

**Fix sketch:** Lazy Live Activity (start 1–2s after overlay visible); single coalesced focus-state publisher; `-PerfTesting` flag skipping health/brain/LA; accessibility marker `uitest-bootstrap-complete`.

**Safety:** Existing deferral of `Activity.request` reduces main-thread block; avoid retaining shell in LA callbacks.

**Tests:** `ADHDViewModelFocusSessionTests` (unit green); stabilize `FocusTimerOpenPerformanceTests` (<100ms / hard 500ms).

**Related:** QA-FOCUS-TIMER-LAG, QA-09, R-016

---

### BUG-008 — Pomodoro session counter resets after every break

| | |
|--|--|
| **Layer** | ViewModel |
| **Files** | `ADHDViewModel.swift` (~L198–205, L255–263, L137–150) |
| **Impact** | After a break ends, `startFocusSession(task:)` forces `currentSessionNumber = 1`. Long-break logic (`sessionsBeforeLongBreak`) never advances across cycles. Users never get scheduled long breaks. |

**RCA:** Break completion path reuses full `startFocusSession`, which resets session metadata for a *new* pomodoro set instead of continuing the set.

**Fix sketch:** Add `startNextFocusInterval(preservingSessionNumber:)` or parameter `resetSessionCounter: Bool = true`; break/skipBreak paths pass `false` and only reset elapsed/target.

**Safety:** No concurrency hazard; pure state machine fix.

**Tests:** Start session → finish focus → finish break → assert `currentSessionNumber == 2`; after N sessions assert long break target.

---

### BUG-009 — Countdown `Timer` double-registered on RunLoop

| | |
|--|--|
| **Layer** | ViewModel |
| **Files** | `ADHDViewModel.swift` `startCountdown` (~L107–123) |
| **Impact** | `Timer.scheduledTimer` already adds to `.default`; extra `RunLoop.main.add(..., .common)` can double-fire ticks → countdown skips 3→1 or finishes early. |

**RCA:** Classic RunLoop double-add. Body-doubling / speech timers only use `scheduledTimer` (OK).

**Fix sketch:** Either `scheduledTimer` **or** `Timer(timeInterval:...)` + `add(forMode: .common)`, not both. Prefer `Task` sleep loop like focus tick.

**Tests:** Start countdown; assert values 3,2,1 over ~3s with no double decrement.

---

### BUG-010 — Gmail disconnect does not delete Keychain token

| | |
|--|--|
| **Layer** | Integrations / Security |
| **Files** | `GmailOAuthService.swift` `disconnect` / `GmailTokenStore` (~L11–58) |
| **Impact** | Disconnect writes empty string; `isConnected` is `loadRefreshToken() != nil` → still true. Empty token left in Keychain; UI may show “connected”. Accessibility defaults weaker than AI key store (no `kSecAttrAccessible`). |

**RCA:** No `SecItemDelete` on disconnect; connection check doesn't treat empty as disconnected.

**Fix sketch:**

```swift
public static func deleteRefreshToken() { SecItemDelete(query) }
public static var isConnected: Bool {
  guard let t = loadRefreshToken(), !t.isEmpty else { return false }
  return true
}
// save: set kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

**Safety:** Improves secret hygiene; add accessibility attribute parity with `KeychainSecretStore`.

**Tests:** connect → disconnect → `isConnected == false` and SecItem not found.

**Related:** LO-DATA-SEC style cases, R-005 family

---

### BUG-011 — Factory reset incomplete for third-party secrets & App Group

| | |
|--|--|
| **Layer** | Data / Privacy |
| **Files** | `FactoryResetManager.swift`; Gmail/Keychain stores; App Group widget/intent stores |
| **Impact** | Local JSON + UserDefaults wiped, but Gmail refresh token, possible AI keychain remnants under legacy service id, and App Group suite data may survive → “factory reset” is not full privacy wipe (R-006). Cloud deletes use `try?` and ignore failures. |

**RCA:** Reset checklist omits Keychain accounts and App Group `UserDefaults(suiteName:)`. Firestore delete swallows errors.

**Fix sketch:** Explicit Keychain wipe list (Gmail, AI keys if product policy says so, messaging tokens); clear App Group stores; surface cloud wipe failures; keep auth session only if documented.

**Tests:** FLOW-008 / LO-IOS-FN-060 — after reset, Gmail disconnected, widget suite empty, no pending captures.

**Related:** R-006

---

### BUG-012 — Auth bootstrap race under fallback UID then Firebase UID swap

| | |
|--|--|
| **Layer** | Auth + Bootstrap |
| **Files** | `FirebaseManager` + `AppShellState.bootstrap` |
| **Impact** | Shell bootstraps under `usr_*`/`guest_*`, loads/seeds tasks, then detached auth replaces UID and calls `reassignTasks`. Concurrent mutations during reassign can orphan or duplicate tasks; analytics/health user keys lag. |

**RCA:** Combination of BUG-001 optimistic auth + async reassignment without suspending bootstrap/orchestration.

**Fix sketch:** Gate bootstrap on stable `Auth.auth().currentUser?.uid` (or explicit guest mode flag); if UID changes mid-flight, cancel bootstrap and restart once.

**Tests:** LO-DATA-SEC-002 style userId mismatch; simulated late anonymous upgrade.

**Related:** R-004, R-008

---

### BUG-013 — Health partial samples → overconfident capacity / Peak risk

| | |
|--|--|
| **Layer** | Health / Brain |
| **Files** | `HealthManager.swift`, `HealthSummaryFreshness`, capacity engines, briefing |
| **Impact** | Sparse HealthKit data can still drive Peak Focus messaging — dangerous for ADHD users planning deep work on poor sleep. |

**RCA:** Risk R-003; thresholds/gating must be strict. Force-unwraps of HK types are safe in practice but indicate brittle assumptions.

**Fix sketch:** Enforce min nights / sample counts before Peak; show confidence + connect prompt (EDGE-D02/D03).

**Tests:** LO-DATA-FN-011, LO-IOS-FN-045 — 1 night sleep never Peak.

**Related:** R-003, EDGE-D02, EDGE-D03

---

### BUG-014 — Planning mutations / GLM schedule still a ship risk

| | |
|--|--|
| **Layer** | AI Planning |
| **Files** | `AIScheduleSlotService`, `PlanMutationApplier`, validators, planning VMs |
| **Impact** | Hallucinated task IDs or illegal moves could still reach apply if any path skips preview/validator. |

**RCA:** Validators exist for slot suggestions; full mutation surface needs guarantee that **no apply path** bypasses schema validation + user preview (R-002).

**Fix sketch:** Single choke-point `applyValidated(_:)` ; reject unknown IDs; deterministic fallback only.

**Tests:** LO-AI-AI-001, FLOW-004 — malformed JSON, unknown IDs, prose+JSON.

**Related:** R-002, EDGE-A03/A04

---

### BUG-015 — Live Activity / widget stale after kill or long background

| | |
|--|--|
| **Layer** | Widget / Execution |
| **Files** | `LiveActivityManager`, `WidgetSyncService`, `ActivityStateController` |
| **Impact** | Stale Lock Screen “now” after process death; wrong task pin until reattach/orchestrate. |

**RCA:** R-016 / R-017. Reattach helpers exist but rely on bootstrap completing and pin flags.

**Fix sketch:** On launch, end orphaned execution activities if schedule snapshot says idle; always reattach then reconcile against TaskStore hero.

**Tests:** FLOW-010, LO-WGT-FN-001.

---

## P2 — Medium

### BUG-016 — Unbounded offline capture queue

No max size in `CaptureOfflineQueue.enqueue`. Disk/JSON growth under long offline use. **Cap + drop-oldest-with-notice.** Related: R-028, BUG-006.

### BUG-017 — NotificationCenter observers in `AppShellState` never removed

`deferralRecoveryObserver` / `taskCompletedObserver` retained for shell lifetime with no `deinit`/`cleanup`. Shell is long-lived so leak is minor; if tests create multiple shells → duplicate handlers. **Add cleanup symmetric to tour coordinator.**

### BUG-018 — Speech recognizer hard-coded `en-US`

`SpeechRecognitionManager` uses `Locale(identifier: "en-US")` only. Non-US English / other languages degrade. **Use `Locale.current` with fallback.** EDGE localization family.

### BUG-019 — Speech `Task { @MainActor }` per audio buffer

Tap handler spawns MainActor tasks at high rate (~buffer frequency) for level meters — main-thread pressure / battery. **Throttle to 10–20 Hz** or sample on timer only (timer already animates idle levels).

### BUG-020 — Email auth uses `email.hashValue` for fallback UID

`abs(email.hashValue)` is **process-unstable** across launches/arch in edge Swift versions and is a weak identity. Combined with BUG-001, same email can map differently if hash ever diverges. **Stable SHA256 of normalized email** if offline id required.

### BUG-021 — Calendar sync errors mostly printed / silent on deny

`syncTodayTasksToAppleCalendar` swallows access denied silently (OK UX) but other errors only `print`. Users get no explanation when write fails. EDGE-P03/P04.

### BUG-022 — Weather still stub

`StubWeatherEnvironmentSignalProvider` — always same weather signal (R-024). Accept for alpha; document in UI so brain doesn't overweight weather.

### BUG-023 — Focus `resetTimer` ignores scheduled window duration

`resetTimer()` resets to `focusDurationMinutes` user default, not `focusDuration(for: task)`. Long fixed blocks reset to 25m mid-session.

### BUG-024 — `resumeFromInterruption` starts fresh session

Uses `startFocusSession` → elapsed zero, session number 1 — does not resume paused elapsed. Misnamed recovery.

### BUG-025 — Body doubling timer not added to `.common` RunLoop

Unlike countdown, scroll/tracking modes may pause timer (inverse of BUG-009). Prefer Task-based tick.

### BUG-026 — Analytics / module badge staleness

R-023/R-025 — TTL refresh and onAppear refresh needed so Insights/badges don't lie.

### BUG-027 — Keychain service string still `com.samaksh.flowos.ai-keys`

Brand migration debt — old service id may strand keys after rename or confuse multi-app access. Ensure migration read path from legacy service.

---

## P3 — Low / tech debt

| ID | Issue | Notes |
|----|--------|------|
| BUG-028 | HK `quantityType(...)!` force unwraps | Types are permanent Apple IDs; still fail-loud if API changes — use guard. |
| BUG-029 | Empty `catch {}` in GLMKeyManager / BriefingDayHero | Swallows useful diagnostics. |
| BUG-030 | `print` used as error channel in production paths | Prefer `os.Logger` + non-PII. |
| BUG-031 | macOS productivity upload failure | R-022 retry queue deferred. |
| BUG-032 | Reduce Motion incomplete | R-027 / LO-IOS-A11Y-020. |
| BUG-033 | iPad safe area | R-026 / EDGE-V12. |
| BUG-034 | Travel / journal export placeholders | R-031/R-032 future. |
| BUG-035 | Double `RunLoop`/Timer patterns elsewhere | Audit remaining timers for `.common` consistency. |

---

## Brain / decision bugs (not software crashes)

Tracked in [brain-bugs.md](brain-bugs.md). Still relevant ship blockers per QA-14:

| ID | Status | Summary |
|----|--------|---------|
| Brain #12 | Open | Sleep-deprived user recommended 90m deep work — executive cost failure |
| Brain #H-001 | Fixed | Hallucinated Adderall when no meds configured |
| Brain #L-003 | Investigating | Repeated gym deferral not shifting schedule (learning-fail) |

Software bugs that amplify brain risk: BUG-003 (stale hero), BUG-013 (bad capacity inputs), BUG-014 (bad plan apply).

---

## Architecture notes (systemic)

```text
Auth (optimistic UID)
   └─► AppShellState.bootstrap (parallel brain/tasks/modules)
         ├─► TaskStore / SQLite (async replace, silent fail)
         ├─► FlowDirector.orchestrate (no serial lock) ──► surface/hero
         ├─► HealthSync ──► capacity ──► briefing
         └─► Widget / Live Activity reconcile
```

| Pattern | Assessment |
|---------|------------|
| `@MainActor` ViewModels | Generally correct |
| BehaviorMemory `actor` | Good isolation |
| Singleton stores (`TaskStore.shared`) | Testability + hidden coupling |
| Fire-and-forget `Task { }` mutations | Optimistic UI OK only with durable await + rollback |
| NotificationCenter fan-out | Easy duplicate work; prefer typed async streams long-term |

---

## Priority remediation plan

### Sprint 0 — ship blockers (P0)

1. Await real Firebase auth; handle nil user (BUG-001, BUG-002, BUG-012).
2. Serialize FlowDirector orchestration + generation token (BUG-003).
3. Make SQLite mutations throwing / awaited; remove `fatalError` open path (BUG-004, BUG-005).
4. Fix offline queue drain-on-failure + cap (BUG-006, BUG-016).

### Sprint 1 — high product pain (P1)

5. Device-verify focus lag; finish UI perf gates (BUG-007).
6. Pomodoro counter + countdown timer (BUG-008, BUG-009).
7. Gmail disconnect + factory reset Keychain/App Group (BUG-010, BUG-011).
8. Capacity gating + planning apply choke-point audit (BUG-013, BUG-014).
9. Live Activity orphan reconcile on launch (BUG-015).

### Sprint 2 — polish (P2/P3)

10. Speech locale/throttle, calendar error UX, resetTimer/resume semantics, logger migration.

---

## Suggested verification matrix

| Suite | Command / target |
|-------|------------------|
| Core unit | `cd Packages/LookAfterCore && swift test` |
| Data unit | `cd Packages/LookAfterData && swift test` |
| Features focus | `swift test --filter ADHDViewModelFocusSessionTests` |
| Flow director | `swift test --filter FlowDirector` (LookAfterAI) |
| UI lag | `FocusTimerOpenPerformanceTests`, `UILagFixPerformanceTests` |
| Flows | FLOW-001 auth, FLOW-002 hero, FLOW-003 capture, FLOW-008 reset, FLOW-010 LA |
| Brain | EVP / LO-COST / LO-LEARN / LO-HALL fixtures |

**Instruments:** Time Profiler + os_signpost around bootstrap, orchestrate, HealthSync, GLM, FocusTimerOpen; Points of Interest for main-thread >16ms; Allocations for speech/LA.

---

## Mapping to existing risk register

| Risk | Bug IDs |
|------|---------|
| R-001 Stale hero | BUG-003 |
| R-002 GLM schedule | BUG-014 |
| R-003 Health Peak | BUG-013 |
| R-004 Auth race | BUG-001, BUG-002, BUG-012 |
| R-005 Key exposure | BUG-010, logging notes |
| R-006 Factory reset | BUG-011 |
| R-016/017 LA/widget | BUG-007, BUG-015 |
| R-028 Offline queue | BUG-006, BUG-016 |

---

## Out of scope / not re-verified here

- Full device Instruments traces
- Production Firebase rules audit
- Complete GLM red-team (see QA-18)
- Exhaustive UI test flake stabilization

---

## Change log

| Date | Change |
|------|--------|
| 2026-08-09 | Initial static audit — 6 P0, 9 P1, 12 P2, 8 P3 + brain cross-ref |
| 2026-08-09 | Branch `fix/bug-audit-remediation`: code fixes for BUG-001–006, 008–011, 013, 015–019, 023–025 |

### Commits on `fix/bug-audit-remediation`

| Commit message | Bugs |
|----------------|------|
| docs(qa): add application bug audit report | — |
| fix(auth): await Firebase auth and handle session end | BUG-001, BUG-002 (+ stable offline UID / BUG-020) |
| fix(flow): serialize FlowDirector orchestration | BUG-003 |
| fix(data): durable task SQLite writes and crash-free DB open | BUG-004, BUG-005 |
| fix(capture): keep failed offline routes and cap queue | BUG-006, BUG-016 |
| fix(focus): preserve pomodoro counter and fix countdown timer | BUG-008, BUG-009, BUG-023, BUG-024, BUG-025 |
| fix(privacy): delete Gmail keychain token and wipe App Group | BUG-010, BUG-011 |
| fix(ios): cleanup observers, speech throttle, orphan Live Activities | BUG-015, BUG-017, BUG-018, BUG-019 |
| fix(capacity): block Peak Focus without fresh sleep evidence | BUG-013 |

---

## Cross-references

- [13-risk-assessment.md](13-risk-assessment.md)
- [14-production-readiness.md](14-production-readiness.md)
- [06-edge-cases.md](06-edge-cases.md)
- [focus-timer-ui-lag.md](focus-timer-ui-lag.md)
- [brain-bugs.md](brain-bugs.md)
- [09-performance-benchmarks.md](09-performance-benchmarks.md)
- [36-failure-recovery.md](36-failure-recovery.md)
