# 9. Performance Benchmarks

**Document ID:** QA-09  
**Parent:** [README.md](README.md)

Performance targets, measurement protocol, and Instruments profiles for LifeOS.

**Reference device:** iPhone 15 class or newer (A16+), iOS 17+, low power mode **off** unless noted.

---

## Benchmark Summary

| Metric | Target | Hard fail | Measurement |
|--------|--------|-----------|-------------|
| Cold launch → Briefing interactive | < 2.5s | > 4.0s | XCTest launch metric / stopwatch |
| Warm launch → Briefing interactive | < 0.8s | > 1.5s | Second launch within 30s |
| Tab transition (Briefing ↔ Work) | 60 fps, < 100ms | Jank > 3 frames | Instruments Core Animation |
| Experience mode switch | < 500ms perceived | > 1.0s | High-speed video / signpost |
| Hero brain refresh after task complete | < 2.0s | > 5.0s | Signpost `orchestrateBrain` |
| GLM first token (planning, WiFi) | < 3.0s | > 8.0s | Network trace |
| GLM full plan parse + apply | < 15.0s | > 30.0s | End-to-end FLOW-004 |
| Task list scroll (500 tasks) | 60 fps | < 45 fps avg | Instruments |
| Health sync 90-day backfill | < 60s | > 120s | HealthSyncService phases |
| Memory steady-state (15 min session) | < 250 MB | > 400 MB | Instruments Allocations |
| CPU steady-state (foreground idle) | < 5% avg | > 15% | Time Profiler |
| Background health observer | < 1% CPU avg | > 5% | Energy Log |
| Widget timeline reload after app update | < 15 min | > 60 min | Manual widget observation |
| Live Activity timer drift (25 min session) | < 2s total | > 5s | Compare system clock |
| Onboarding step transition | < 300ms | > 800ms | Animation signpost |
| Inbox AI process (single item) | < 5s | > 15s | Network + parse |
| Focus timer open (Today → Start now → timer visible) | < 100ms | > 500ms | `FocusTimerOpenPerformanceTests` |
| Focus timer pause / resume label update | < 100ms | > 500ms | `FocusTimerOpenPerformanceTests` |
| Focus timer stop → dismiss overlay | < 100ms | > 500ms | `FocusTimerOpenPerformanceTests` |
| Focus session state activation (ViewModel) | < 16ms | > 50ms | `ADHDViewModelFocusSessionTests` |

**Release tolerance:** Within **10%** of target on reference device.

---

## Measurement Protocol

### Cold launch

1. Force quit app  
2. Clear DerivedData not required; optional reboot for cleanest baseline  
3. Launch with Instruments App Launch template OR XCTest `measure(metrics: [XCTApplicationLaunchMetric()])`  
4. Start timer at icon tap; stop when hero CTA is tappable  
5. Repeat 5 runs; discard first; average runs 2–5  

### Warm launch

1. Launch app → background 30s → foreground  
2. Measure time to interactive Briefing  

### Brain refresh

1. Add signpost in `AppShellState.orchestrateBrain`  
2. Complete hero task  
3. Measure signpost interval until `brainVM` publishes new hero  

### GLM latency

1. Staging API key on WiFi  
2. Network Instruments on planning conversation  
3. Record TTFB and full response  

### Memory

1. Instruments Allocations  
2. Exercise: launch → all tabs → open 3 modules → planning sheet → dismiss  
3. Mark heap after 5 min idle  

### Scroll

1. Seed 500 tasks via test account  
2. Core Animation instrument; fast fling on TaskListView  
3. Record frame rate graph  

---

## Instruments Profiles

| Profile | Use case |
|---------|----------|
| App Launch | Cold/warm launch |
| Time Profiler | CPU hotspots in orchestrate |
| Allocations | Memory leaks in ViewModels |
| Leaks | Retain cycles in sheets |
| Energy Log | Background health observers |
| Network | GLM/Firebase calls |
| Core Animation | Scroll and transitions |

---

## Performance Test Cases

### LO-IOS-PERF-001 — Cold launch

| Priority | P0 |
| Target | < 2.5s |
| Steps | FLOW-001 cold start on physical device |
| Fail | Spinner > 4s; blank hero > 3s |

### LO-IOS-PERF-002 — Warm launch

| Priority | P1 |
| Target | < 0.8s |

### LO-IOS-PERF-003 — Tab switch frame rate

| Priority | P1 |
| Target | 60 fps |
| Screens | All 5 tabs |

### LO-IOS-PERF-004 — Mode switch animation

| Priority | P1 |
| Target | < 500ms |

### LO-IOS-PERF-005 — Hero brain refresh

| Priority | P0 |
| Target | < 2.0s |
| Linked | LO-IOS-FN-001 |

### LO-AI-PERF-001 — GLM planning latency

| Priority | P0 |
| Target | First token < 3s; full < 15s |

### LO-IOS-PERF-014 — Task list 500 scroll

| Priority | P1 |
| Target | 60 fps |

### LO-DATA-PERF-001 — Health backfill

| Priority | P1 |
| Target | < 60s for 90 days |

### LO-IOS-PERF-020 — Memory steady-state

| Priority | P1 |
| Target | < 250 MB |

### LO-DATA-PERF-002 — Background CPU

| Priority | P2 |
| Target | < 1% avg over 1 hour |

### LO-WGT-PERF-001 — Widget refresh latency

| Priority | P2 |
| Target | < 15 min after app hero change |

---

## Battery Impact Scenarios

| Scenario | Duration | Acceptable drain |
|----------|----------|------------------|
| Active use (planning + tasks) | 30 min | < 5% on full battery |
| Background health observers | 8 hours | < 3% overnight |
| Focus session + Live Activity | 25 min | Comparable to timer apps |
| macOS productivity tracker | 8 hours | < 2% laptop battery |

---

## Performance Regression Gates

| Tier | When | Action if fail |
|------|------|----------------|
| Smoke | Pre-merge | Investigate if > 25% regression |
| Release | Pre-TestFlight | Block if hard fail threshold hit |
| Soak | 48h TestFlight | Investigate crash/energy reports |

---

## Signpost Recommendations (for engineering)

Add os_signposts around:

- `AppShellState.bootstrap`  
- `AppShellState.orchestrateBrain`  
- `FlowDirector.orchestrate`  
- `HealthSyncService.ensureSynced`  
- `GLMService.complete`  
- `TasksViewModel.loadTasks`  

Enables automated perf tests in future XCTest metrics.

---

## Results Log Template

| Benchmark | Run 1 | Run 2 | Run 3 | Avg | Pass | Device | Build |
|-----------|-------|-------|-------|-----|------|--------|-------|
| Cold launch | | | | | | | |
| Hero refresh | | | | | | | |
| GLM planning | | | | | | | |
