# 37. UI Lag Fix Performance Scorecard

**Document ID:** QA-37  
**Branch:** `performance/ui-lag-fixes`  
**Parent:** [09-performance-benchmarks.md](./09-performance-benchmarks.md)

Validates every fix from the UI lag remediation with **target**, **hard fail**, and a **0–100 score**.  
**Acceptable pass:** score **≥ 70** (under hard fail). **Excellent:** score **≥ 90** (near target).

---

## Scoring formula

Implemented in `PerformanceBudgets.score(durationMs:targetMs:hardFailMs:)`:

| Duration | Score |
|----------|-------|
| ≤ target | **100** |
| Between target and hard fail | **70–99** (linear) |
| = hard fail | **~69** → fail |
| ≥ 2× hard fail | **0** |

`isAcceptable(score)` → `score >= 70`.

---

## Scenario matrix (what each test proves)

| ID | Fix under test | Layer | Test class | Target | Hard fail | Accept |
|----|----------------|-------|------------|--------|-----------|--------|
| PERF-UNIT-FOCUS-START | Instant focus state flip | L1 unit | `ADHDViewModelFocusSessionTests` | 16ms | 50ms | ≥70 |
| PERF-UNIT-FOCUS-PAUSE | Pause label state | L1 | same | 16ms | 50ms | ≥70 |
| PERF-UNIT-FOCUS-STOP | Stop clears overlay state | L1 | same | 16ms | 50ms | ≥70 |
| PERF-UNIT-SORT-100 | Task list memoization dependency | L1 | `PerformanceMonitorTests` | 16ms | 50ms | ≥70 |
| PERF-UNIT-SORT-500 | Large list sort budget | L1 | same | 50ms | 150ms | ≥70 |
| PERF-UNIT-SCORECARD | Scoring helper | L1 | same | n/a | n/a | assertions |
| PERF-UNIT-SAVE-RETURN | JSON I/O off main (return fast) | L1 | `LocalPersistencePerformanceTests` | 50ms | 200ms | ≥70 |
| PERF-UNIT-SAVE-ASYNC | 200-task write + load | L1 | same | 500/200ms | 2000/1000ms | ≥70 |
| PERF-UNIT-SAVE-RACE | Barrier load sees pending save | L1 | same | correctness | — | pass |
| PERF-UNIT-CTX-REFRESH | Batched orchestrator refresh | L1 | `ContextOrchestratorPerformanceTests` | 200ms | 1000ms | ≥70 |
| PERF-UNIT-CTX-WARM | Warm second refresh | L1 | same | 150ms | 800ms | ≥70 |
| PERF-UNIT-CTX-BATCH | snapshot+brain+briefing cohere | L1 | same | correctness | — | pass |
| PERF-UNIT-COALESCE | StateCoalescer latest-only | L1 | `StateCoalescerPerformanceTests` | correctness | 50ms/100 ops | pass |
| PERF-UI-FOCUS-OPEN | Deferred Live Activity path | L2 UI | `FocusTimerOpenPerformanceTests` / `UILagFixPerformanceTests` | 100ms | 500ms | ≥70 |
| PERF-UI-FOCUS-STOP | Stop dismiss overlay | L2 | `UILagFixPerformanceTests` | 100ms | 500ms | ≥70 |
| PERF-UI-TAB-TODAY | Tab transition | L2 | same | 200ms | 1000ms | ≥70 |
| PERF-UI-TASK-LIST | Task list open + filter cache | L2 | same | 500ms | 2000ms | ≥70 |
| PERF-UI-MULTI-TAB | Steady shell multi-tab | L2 | same | 1500ms | 4000ms | ≥70 |
| PERF-UI-WARM-LAUNCH | Warm launch | L2 | `PerformanceBenchmarkTests` | 800ms | 1500ms | ≥70 |

---

## User scenarios (manual + automated)

| User journey | Automated? | Pass criteria |
|--------------|------------|---------------|
| Open app → Briefing interactive | UI launch metric | Warm < 1.5s hard |
| Briefing ↔ Today tabs | `testBriefingToToday…` | < 1s hard |
| Open all tasks list, scroll | task list open + sort unit | open < 2s; sort score ≥70 |
| Start focus from Today timeline | focus open tests | < 500ms hard |
| Pause / resume / stop focus | unit + UI stop | state < 50ms; UI stop < 500ms |
| Complete task → brain updates | context refresh unit | score ≥70 |
| Background → foreground | existing lifecycle | no freeze > 1s (manual) |
| Health connect / sync | parallel HealthKit (manual Instruments) | sync < 3s typical device |

---

## How to run

```bash
# Unit — Core
cd Packages/LookAfterCore && swift test --filter PerformanceMonitorTests

# Unit — Data persistence I/O
cd Packages/LookAfterData && swift test --filter LocalPersistencePerformanceTests

# Unit — Features (focus, orchestrator, coalescer)
cd Packages/LookAfterFeatures && swift test --filter 'ADHDViewModelFocusSessionTests|ContextOrchestratorPerformanceTests|StateCoalescerPerformanceTests'

# UI (simulator, Xcode)
xcodebuild test -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LookAfterUITests/UILagFixPerformanceTests \
  -only-testing:LookAfterUITests/FocusTimerOpenPerformanceTests \
  -only-testing:LookAfterUITests/PerformanceBenchmarkTests
```

Evidence JSON: `Documentation/qa/.engine/evidence/PERF-*.json`

---

## Release gate (composite)

| Gate | Rule |
|------|------|
| **Ship** | All L1 unit perf tests green; no L2 hard-fail; composite average score ≥ **80** where scored |
| **Hold** | Any hard-fail on focus open, warm launch, or context refresh |
| **Investigate** | Score 70–79 on two or more scenarios |

Composite (manual sheet): average of scored unit metrics (sort 100/500, save return, ctx refresh/warm, focus activation) + UI focus open if available.

---

## Mapping fix → proof

1. **Batch @Published** → `ContextOrchestratorPerformanceTests`
2. **Parallel HealthKit** → Instruments / manual Health sync (unit covered indirectly via faster app path)
3. **JSON I/O queue** → `LocalPersistencePerformanceTests`
4. **Task filter memoization** → sort budgets + `testTaskListOpensWithinBudget`
5. **Deferred Live Activity** → focus UI tests with `-SkipLiveActivity` + device retest without skip
6. **Context loop guards** → no freeze during focus (UI focus open stable)
7. **PerformanceMonitor / Budgets** → `PerformanceMonitorTests` scorecard tests

---

## Sample scorecard worksheet

| Scenario | Measured ms | Target | Hard fail | Score | Accept (≥70)? |
|----------|-------------|--------|-----------|-------|---------------|
| Focus VM start | | 16 | 50 | | |
| Focus UI open | | 100 | 500 | | |
| Context refresh | | 200 | 1000 | | |
| Warm context refresh | | 150 | 800 | | |
| Save return | | 50 | 200 | | |
| Sort 100 tasks | | 16 | 50 | | |
| Sort 500 tasks | | 50 | 150 | | |
| Tab Briefing→Today | | 200 | 1000 | | |
| Task list open | | 500 | 2000 | | |
| Warm launch | | 800 | 1500 | | |
| **Composite average** | | | | | **Ship if ≥80** |

---

## Related files

| File | Role |
|------|------|
| `PerformanceBudgets.swift` | Targets, hard fails, score formula |
| `PerformanceMonitor.swift` | DEBUG timing + signposts |
| `ADHDViewModelFocusSessionTests.swift` | Focus VM budgets |
| `LocalPersistencePerformanceTests.swift` | I/O queue |
| `ContextOrchestratorPerformanceTests.swift` | Batched refresh |
| `StateCoalescerPerformanceTests.swift` | Coalesce helper |
| `PerformanceMonitorTests.swift` | Sort + scorecard unit |
| `UILagFixPerformanceTests.swift` | UI journey budgets |
| `FocusTimerOpenPerformanceTests.swift` | Focus open/pause/stop UI |
| `PerformanceBenchmarkTests.swift` | Launch + tab baseline |
