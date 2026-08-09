# Deep Performance Analysis

**Document ID:** QA-PERF-DEEP  
**Date:** 2026-08-09  
**Branch:** `fix/bug-audit-remediation`  
**Scope:** Static deep dive beyond PERF-001…009  
**Method:** Hot-path code review (ViewModels, SQLite, SwiftUI lists, scheduling, focus tick)

---

## Executive scorecard

| Area | Health | Top issue |
|------|--------|-----------|
| Focus session publish | **Improved** | Overlay 1 Hz; shell should use `focusDisplayElapsed` (5s) — **PERF-014 fixed** |
| Task list SwiftUI | **Improved** | Animation on revision; batched time-display — **PERF-012/013/017 fixed** |
| Task persistence | **Improved** | Upsert/delete-by-id on mutation paths — **PERF-011 fixed** |
| Schedule reconcile | Fair | Many loops still O(n) with linear lookups; partially batched |
| Context / brain loop | Good | Mitigated (90s + alternate light refresh) |
| Live Activity fan-out | Good | Coalesced |
| Codecs / formatters | **Improved** | `SharedFormatters` — **PERF-018** (migrate remaining call sites over time) |
| Large lists | Mixed | Inbox uses LazyVStack; TaskList thrash reduced |

---

## Implementation status (code landed)

| ID | Status | Commit theme |
|----|--------|--------------|
| PERF-011 | **Fixed** | `upsert` / `upsertMany` / `deleteIds`; repo create/update/delete use them |
| PERF-012 | **Fixed** | TaskList animates `tasksContentRevision` |
| PERF-013 | **Fixed** | Stage local displays → one publish; AI refine concurrent×3 |
| PERF-014 | **Fixed** | `focusDisplayElapsed` 5s buckets; overlay keeps 1 Hz elapsed |
| PERF-015 | **Fixed** | Cached `schedulingContext` / `activeTasks` until revision |
| PERF-016 | **Fixed** | `taskIndex` + `applyInMemoryTaskUpdate` on hot mutate paths |
| PERF-017 | **Fixed** | Cap 40 tasks + concurrent refine group |
| PERF-018 | **Partial** | SharedFormatters + CaptureGraph / GLM usage / Firestore |
| PERF-019 | **Fixed** | `ADHDOverlayHost` isolates focus/emergency from root canvas |
| PERF-020 | **Fixed** | DaySchedulePlanner id maps + O(slotted) existingTasks |
| PERF-021 | **Fixed** | Prompt task limit 20 (max 40); shared time formatter; missed capped |

---

## Critical (ship-risk under load)

### PERF-011 — SQLite `replaceAll` is O(all tasks) per mutation **(FIXED)**

**Where:** `TaskSQLiteStore.replaceAll`  
```text
deleteAll(db) + for task in tasks { insert }
```
**Callers:** `TaskRepository.create/update/updateMany/delete` → every durable write.

**Impact:**  
With 200–500 tasks (EDGE-D07), a single toggle complete rewrites the entire table + re-encodes every `LifeTask` (large Codable graph: steps, semanticProfile, tags…).  
Even `updateMany` only reduces *N calls* to *1 call* — that call is still O(total tasks), not O(changed).

**Why fixed PERF-005 is incomplete:** Batching cut multiply-by-N, not the full-table algorithm.

**Fix direction:**
1. Upsert-by-id / delete-by-id for single mutations.  
2. Keep `replaceAll` only for migration / factory reset / compact.  
3. Encode only dirty rows; store semanticProfile as separate blob column if needed.

**Estimate:** P0 for large accounts; P1 for light users.

---

### PERF-012 — TaskList animation recomputes full ID list on every body pass

**Where:** `TaskListView.swift`  
```swift
.animation(.spring(...), value: cachedFilteredTasks.map(\.id))
```

**Impact:** Every SwiftUI body evaluation allocates a new `[String]` of all visible task IDs and compares for animation. During scroll / `@Published` churn this is pure main-thread waste and can fight List diffing.

**Fix:** Animate on `tasksContentRevision` or a cached `filteredIdsSignature: Int` updated only when filter content changes.

---

### PERF-013 — Time-display refinement thrashing TaskList via `@Published` dictionaries

**Where:** `TasksViewModel`  
- `@Published taskTimeDisplays`  
- `@Published loadingTimeDisplayTaskIds`  
`refreshTimeDisplays` mutates these **per task**, and may await GLM refine serially.

**Impact:** Each dictionary assignment → `objectWillChange` → **entire** TaskList (and any other observer of `TasksViewModel`) re-renders. With smarter focus tips ON and 30 visible tasks → up to 30+ full list invalidations + possible sequential network.

**Fix:**
1. Don’t `@Publish` the full dictionary; publish a `timeDisplayEpoch` and read from a non-published cache, **or**  
2. Batch end-of-pass single publish.  
3. Cap concurrent AI refine (e.g. 3) + only visible IDs.  
4. Split `TaskListRowView` to observe a per-row model / `Equatable` row props only.

---

### PERF-014 — Focus elapsed publishes every second to global observers

**Where:** `ADHDViewModel.startFocusTimer` → `focusSessionElapsed += 1` each second (`@Published`).

**Impact:** Correct for overlay clock, but any parent holding `@ObservedObject var adhdVM` (shell modifiers, root) re-renders **every second** for the whole observed subtree. This is a prime contributor to residual focus UI lag (PERF-010 / BUG-007) when LA + widget + shell all observe the same VM.

**Fix:**
1. Keep high-frequency elapsed in a non-`@Published` / `CurrentValueSubject` consumed only by overlay.  
2. Publish `focusProgressBucket` (already sparse) + a 5s “coarse elapsed” for non-overlay UI.  
3. Ensure shell modifiers observe only coarse flags (`isFocusSessionActive`, `isPaused`), not the full VM — use focused `onChange` of specific properties (already partial).

---

## High

### PERF-015 — `schedulingContext` rebuilds concatenated arrays repeatedly

**Where:** `TasksViewModel.schedulingContext`  
```swift
taskStore?.snapshot.schedulingContext ?? (tasks + completedToday + recurrenceTemplates)
```

**Impact:** Called from schedule mutations / allocate / resolve paths; allocates large temporary arrays. Snapshot path is OK if TaskStore caches; fallback concatenates every read.

**Fix:** Ensure TaskStore snapshot always warm; cache `schedulingContext` until content revision bumps.

---

### PERF-016 — Linear `firstIndex` / `first(where:)` inside O(n) loops

**Where:** `TasksViewModel` (~85 filter/map/firstIndex sites), `DaySchedulePlanner`, `ConflictResolutionCascade`, `PlanningPromptContextBuilder`.

**Pattern:**  
```swift
for id in changedIDs {
  if let index = tasks.firstIndex(where: { $0.id == id }) { ... }
}
```
→ O(n·m). With n=500, m=50 allocate → 25k comparisons on MainActor.

**Fix:** Build `Dictionary(uniqueKeysWith:)` / `uniquingFirstValue` once per pass; index by id.

---

### PERF-017 — Serial AI time-display refine

**Where:** `refreshTimeDisplays` `for task in tasks { await refine... }`

**Impact:** Multiplies GLM latency by task count when tips enabled; holds `loadingTimeDisplayTaskIds` churn.

**Fix:** `withTaskGroup` limited concurrency; only `.prefix(visible)` or on-screen IDs.

---

### PERF-018 — Per-call `JSONEncoder` / `DateFormatter` / `ISO8601DateFormatter`

**Where (samples):** DecisionHistoryStore, GLMUsageLogger, CascadeDistiller, FocusWindowFormatter, TagChipView, LifeTimelinePresenter, LookAfterV4Components, AuthProxyClient.

**Impact:** Formatter init is expensive; hot UI formatters in row bodies can cost ms each during scroll.

**Fix:** `static let` formatters (thread-safe DateFormatter via lock or cached on MainActor); shared JSONEncoder with date strategy like TaskSQLiteStore.

---

## Medium

### PERF-019 — Observation surface too wide at shell

`AppShellState` + many `@Published` children; views taking whole `shell` as `ObservedObject` re-render on any nested publish (brain, briefing, tasks, modules).

**Fix:** Pass down focused VMs / use `EquatableView` / split observation; prefer bindings of coarse state.

### PERF-020 — Planner / conflict cascade algorithmic weight

`DaySchedulePlanner` + cascade: many filter/map passes over day tasks per reconcile. Acceptable for <100 day tasks; can spike with dense calendars + AI reschedule.

**Fix:** Precompute interval indexes; single pass occupancy bitmap by minute.

### PERF-021 — Prompt context builders scan full task lists

`PlanningPromptContextBuilder` multiple filters over all tasks to build GLM context → CPU + large prompts → higher GLM cost/latency (not just device CPU).

**Fix:** Cap tasks sent (already partial via today filter — verify hard caps); summarize instead of full dump.

### PERF-022 — Widget/timeline rebuild still heavy when fingerprint changes

Fingerprint is cheaper (PERF-009), but a real change still rebuilds full `WidgetSnapshot` + JSON to App Group.

**Fix:** Incremental pin-only update path when only hero title changes.

### PERF-023 — Health sync still multi-query

HealthKit auth + sleep + HR + HRV + steps on refresh path. Light refresh skip helps (PERF-003); ensure pull-to-refresh doesn’t stack concurrent `ensureSynced`.

### PERF-024 — String `print` logging on hot paths

Task cascade / recurrence paths still `print` in release-adjacent builds.

**Fix:** `os.Logger` with `.debug` and compile-out or privacy levels.

---

## Low / polish

| ID | Issue |
|----|--------|
| PERF-025 | `LifeTask` value type very large — array copies expensive; consider `class` cache or COW wrappers for store |
| PERF-026 | `List` spring animation on task complete may layout thrash |
| PERF-027 | GeneratedTasksReview / some ScrollViews may lack Lazy* for big seed batches |
| PERF-028 | Background analytics full recomputes — ensure only on `lastRefreshAt` change (already mostly gated) |

---

## Interaction with already-fixed items

| Fixed | Residual risk |
|-------|----------------|
| PERF-001 LA coalesce | Still need sparse elapsed publish (PERF-014) |
| PERF-002 notification debounce | Good |
| PERF-005 updateMany | Algorithm still full table (PERF-011) |
| PERF-007 cancelable timers | Good |
| PERF-010 device lag | Driven by PERF-014 + ActivityKit cold start |

---

## Priority fix order (recommended)

| Priority | ID | Effort | Expected win |
|----------|-----|--------|----------------|
| 1 | PERF-011 upsert SQLite | L | I/O cliffs on every edit |
| 2 | PERF-014 sparse focus publish | M | Focus UI FPS / shell idle CPU |
| 3 | PERF-013 time-display publish batching | M | Task list jank with tips on |
| 4 | PERF-012 animation value | S | Easy scroll CPU win |
| 5 | PERF-016 id-index maps in reconcile | M | Large-account schedule |
| 6 | PERF-018 static formatters | S | Scroll/list cells |
| 7 | PERF-017 concurrent refine cap | S | AI tips latency |

---

## Suggested Instruments matrix

| Suspect | Instrument | Signpost / filter |
|---------|------------|-------------------|
| PERF-011 | Time Profiler + File Activity | `TaskSQLiteStore`, `replaceAll` |
| PERF-012/013 | SwiftUI / Core Animation | TaskList scroll with 200 tasks |
| PERF-014 | Time Profiler | 60s focus session, main thread samples |
| PERF-020 | Time Profiler | `DaySchedulePlanner`, force replan |
| Launch | App Launch | cold start hero tappable |

---

## Acceptance targets (add to QA-09)

| Scenario | Target | Hard fail |
|----------|--------|-----------|
| Complete 1 task @ 300 tasks in store | < 50ms local persist | > 200ms |
| Task list scroll 60fps @ 200 rows | ≥ 55fps | < 45fps |
| Focus session shell CPU | < 3% main avg | continuous > 8% |
| Time-display refresh 20 rows local-only | < 30ms | > 100ms |

---

## Out of scope of this document

- Device measurement of BUG-007 (still required)  
- Server-side GLM p95 (separate SLO)  
- Widget process CPU on Home Screen  

---

## Related docs

- [PERFORMANCE-AUDIT.md](PERFORMANCE-AUDIT.md) — PERF-001…010 status  
- [09-performance-benchmarks.md](09-performance-benchmarks.md)  
- [focus-timer-ui-lag.md](focus-timer-ui-lag.md)  
- [BUG-AUDIT-REPORT.md](BUG-AUDIT-REPORT.md)  
