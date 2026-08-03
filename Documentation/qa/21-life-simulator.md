# 21. Life Simulator Validation

**Document ID:** QA-21  
**Validation Layer:** L4-S  
**Parent:** [README.md](README.md)

Synthetic multi-day simulation of a virtual human to surface bad planning patterns invisible to single-scenario tests.

---

## Purpose

Drive [`ExecutiveBrainEngine`](../../Packages/ExecutiveBrain/Sources/ExecutiveBrain/Engine/ExecutiveBrainEngine.swift) over 30–365 simulated days with deterministic clock. Aggregate DQS, Executive Cost, and trust proxies.

---

## Virtual Human Profiles

| Profile ID | Traits |
|------------|--------|
| SIM-PROFILE-001 | ADHD adult, 9–5 job, gym Tue/Thu |
| SIM-PROFILE-002 | Freelancer, irregular sleep |
| SIM-PROFILE-003 | Parent, fragmented calendar |

---

## Test Cases

### SIM-001 — Monday OAuth deadline week (30 days)

| Field | Value |
|-------|-------|
| Priority | P0 |
| Validation Layer | L4-S |
| Scenario | 30-day run with recurring meetings + one hard deadline |
| Preconditions | Fixture `fixtures/simulator/sim_001_30day.json` |
| Steps | Run `./evp simulate --days 30 --scenario SIM-001` |
| Expected | No S1 brain bugs; mean totalBurden ≤ doc 19 baseline |
| Automation | LifeSimulatorRunner (Phase 2 full; Phase 1 scaffold) |

### SIM-002 — Sleep deprivation spiral

| Field | Value |
|-------|-------|
| Priority | P1 |
| Validation Layer | L4-S |
| Scenario | 7 nights <5h sleep |
| Expected | Brain recommends recovery before deep work ≥80% of low-sleep mornings |

### SIM-DAY-001 — Single day smoke

| Field | Value |
|-------|-------|
| Priority | P0 |
| Validation Layer | L4-S |
| Steps | `./evp simulate --days 1 --scenario SIM-DAY-001` |
| Expected | Completes without crash; decision log non-empty |

---

## Aggregate Metrics

| Metric | Threshold (30-day) |
|--------|-------------------|
| Mean DQS | ≥ 3.5 |
| Mean totalBurden | ≤ baseline from doc 19 |
| Regret proxy events | ≤ 3 |
| Goal completion rate | ≥ 40% |

---

## Fixtures

See [fixtures/simulator/](fixtures/simulator/README.md).
