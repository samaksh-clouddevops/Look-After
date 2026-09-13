# Performance Audit

**Document ID:** QA-PERF-AUDIT  
**Date:** 2026-08-09  
**Branch:** `fix/bug-audit-remediation`  
**Related:** [09-performance-benchmarks.md](09-performance-benchmarks.md), [focus-timer-ui-lag.md](focus-timer-ui-lag.md), [BUG-AUDIT-REPORT.md](BUG-AUDIT-REPORT.md)

---

## Summary

Static performance review of hot paths (context loop, focus Live Activity fan-out, task-list notification thrash, SQLite N×replace, speech meters).

| ID | Severity | Issue | Status |
|----|----------|--------|--------|
| **PERF-001** | High | Multiple `onChange` handlers each sync Live Activity on focus start | **Fixed** — coalesced |
| **PERF-002** | High | `.taskListDidChange` regenerates cognitive snapshot + briefing on every mutation | **Fixed** — 120ms debounce |
| **PERF-003** | Medium | 60s context loop always ran full `refreshContext` (schedule reconcile + health) | **Fixed** — 90s + alternate light refresh |
| **PERF-004** | Medium | Speech level `@Published` at 20 Hz + idle random rewrite | **Fixed** — 10 Hz |
| **PERF-005** | High | Day boundary / slot allocate called `taskRepo.update` per task (N full SQLite rewrites) | **Fixed** — `updateMany` (+ more loops) |
| **PERF-006** | Medium | `.scheduleDidChange` immediately rebuilt widgets + briefing | **Fixed** — 150ms coalesce |
| **PERF-007** | Medium | `DailyPlanView` / PhysiologicalReset 1 Hz `Timer.publish` while visible | **Fixed** — cancelable Task ticks |
| **PERF-008** | Medium | Always-on V4 ripple / shimmer animations | **Mostly fixed** — Reduce Motion on V4 orb, shimmer, appear, sleep pulse |
| **PERF-009** | Low | Widget fingerprint rebuilds full task id join each sync | **Fixed** — count + hash sample |
| PERF-010 | Known | Focus UI lag on device (ActivityKit) | Open — device verify BUG-007 |

---

## Root causes & fixes

### PERF-001 — Focus Live Activity thrash

**Where:** `ExperienceRootFocusModifier` — separate `onChange` for pause, break, target, progress.

**Why it hurts:** Session start flips 4–5 `@Published` properties → 4–5 ActivityKit updates → main-thread jank (links to BUG-007).

**Fix:** Coalesce progress/pause/break/target into one 50ms deferred `syncFocusActivity`.

### PERF-002 / PERF-006 — Notification fan-out

**Where:** `ExperienceRootDataModifier` on `.taskListDidChange` / `.scheduleDidChange`.

**Why:** Reconcile posts many notifications → each run regenerates cognitive snapshot + briefing + widget path.

**Fix:** Keep cheap VM sync immediate; debounce heavy brain/briefing/widget work (120–150ms).

### PERF-003 — Context loop cost

**Where:** `AppShellState.startContextLoop` every 60s → full `refreshContext`.

**Why:** Full path warms tasks, force recurrence, health refresh, orchestrate, timeline rebuild.

**Fix:** 90s interval; even ticks full refresh, odd ticks `refreshBriefingSurface` without health.

### PERF-005 — N SQLite full replaces

**Where:** Day-boundary sweep + AI slot apply + local allocate loops each `await taskRepo.update`.

**Why:** Each update is full-table `replaceAll` → O(n × tasks) disk I/O on main actor.

**Fix:** `TaskRepository.updateMany` + batch at call sites.

### PERF-004 — Speech meter

**Where:** `SpeechRecognitionManager` 50ms timer rewriting `audioLevels`.

**Fix:** 100ms timer on `.common` run loop.

---

## Remaining recommendations (not coded)

1. **Device profile focus open** with Instruments Time Profiler + os_signpost `FocusTimerOpen` (BUG-007 / PERF-010).
2. **LazyVStack** audit on task lists with 200+ rows (EDGE-D07).
3. **Move GLM JSON encode** for large prompts fully off MainActor if not already.
4. Single-task `update` paths are fine; remaining multi-mutate loops can adopt `updateMany` opportunistically.

---

## Budgets (from PerformanceBudgets)

| Path | Target | Hard fail |
|------|--------|-----------|
| Focus VM activate | 16ms | 50ms |
| Focus UI open | 100ms | 500ms |
| Context refresh | 200ms | 1000ms |
| Warm context | 150ms | 800ms |

---

## Commits

| Message | PERF IDs |
|---------|----------|
| fix(perf): coalesce focus Live Activity and task-list fan-out | PERF-001, 002, 006 |
| fix(perf): lighten context loop interval and alternate refresh | PERF-003 |
| fix(perf): reduce speech level meter publish rate | PERF-004 |
| fix(perf): batch SQLite updates for cascade and slot allocate | PERF-005 |
| fix(perf): cancelable task timers for reset and visual focus | PERF-007 |
| fix(perf): cheaper widget snapshot fingerprint | PERF-009 |
| fix(perf): batch more recurrence and supersede SQLite updates | PERF-005 |

---

## How to verify

```bash
# Unit
cd Packages/LookAfterFeatures && swift test --filter 'ADHDViewModelFocusSessionTests|StateCoalescerPerformanceTests'
cd Packages/LookAfterData && swift test --filter LocalPersistencePerformanceTests

# UI (device preferred)
xcodebuild test -scheme LookAfter-iOS \
  -only-testing:LookAfterUITests/FocusTimerOpenPerformanceTests \
  -only-testing:LookAfterUITests/UILagFixPerformanceTests
```

Instruments: Time Profiler + Points of Interest (`FocusTimerOpen`, `ContextRefresh`, `HealthSync`, `OrchestrateBrain`).
