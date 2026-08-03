# 15. Decision Quality Framework

**Document ID:** QA-15  
**Parent:** [README.md](README.md)  
**Priority:** P0 — product moat validation

---

## Why this document exists

Traditional QA asks: *Did the Brain recommend the gym?*

Decision Quality asks: *Was the gym actually the best decision for this user, in this state, at this moment?*

A recommendation can pass every functional, performance, and accessibility test and still **harm the user** by optimizing the wrong objective. Decision Quality is LifeOS's primary product quality metric — separate from bugs.

**Related:** [19-executive-cost-validation.md](19-executive-cost-validation.md), [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md), [brain-bugs.md](brain-bugs.md)

---

## Decision vs Bug

| Type | Example | Tracker |
|------|---------|---------|
| **Bug** | App crashes on hero tap | Issue tracker / S1–S4 |
| **Brain mistake** | Recommends 90min deep work after 4h sleep | [brain-bugs.md](brain-bugs.md) / `brain-decision` label |
| **Decision quality fail** | Chose gym when walk had lower Executive Cost | This framework |

---

## Scoring dimensions (every recommendation)

Each issued recommendation (hero intent, planning mutation, coach suggestion with action) is scored on **8 dimensions**:

| # | Dimension | Definition | Scale | Weight |
|---|-----------|------------|-------|--------|
| 1 | **Executive Cost reduction** | Did this choice minimize `ExecutiveCost.totalBurden` vs alternatives? | 0–5 | 20% |
| 2 | **Stress reduction** | Net stress delta after 6h (observed or simulated) | 0–5 | 15% |
| 3 | **Energy optimization** | Aligns with current + predicted energy curve | 0–5 | 15% |
| 4 | **Goal progress** | Advances stated `userKeyGoals` / life model priorities | 0–5 | 15% |
| 5 | **User satisfaction (post-execution)** | User rating after attempting recommendation | 0–5 | 15% |
| 6 | **Regret avoided** | User did not wish they had chosen differently | 0–5 | 10% |
| 7 | **Confidence calibration** | Stated confidence matches outcome (not over/under) | 0–5 | 5% |
| 8 | **Explainability** | User understands why-now without support | 0–5 | 5% |

**Decision Quality Score (DQS):**

```
DQS = Σ(dimension_score × weight)   // max 5.0
```

| DQS | Verdict |
|-----|---------|
| ≥ 4.0 | **Correct decision** — ship-quality |
| 3.0–3.9 | **Acceptable** — monitor; may need copy or weight tuning |
| 2.0–2.9 | **Suboptimal** — log as brain-decision; P1 fix |
| < 2.0 | **Wrong decision** — log as brain-bug; P0 if health/safety |

---

## Evaluation record template

Use for every audited recommendation:

```markdown
### DQ-EVAL-{NNN}

**Date:** YYYY-MM-DD  
**User persona:** P1 / P2 / staging fixture  
**Session ID:** (optional)

#### Context snapshot
- Sleep: __h __m | HRV: __ | Energy band: __
- Calendar density: __ meetings | Cognitive load: __
- Pending tasks: __ | Hero task: __
- Cycle phase: __ (if applicable)
- Medication window: __

#### Decision issued
| Field | Value |
|-------|-------|
| **Recommendation** | e.g. Workout — 45 min gym |
| **Intent type** | ExecutiveIntent / hero / planning mutation |
| **Confidence** | 0.__ |
| **Why-now (system)** | … |
| **Executive Cost (chosen)** | totalBurden = __ |

#### Alternatives considered
| Alternative | Exec Cost (manual) | Exec Cost (system) | Notes |
|-------------|-------------------|-------------------|-------|
| Sleep / nap | | | |
| Continue coding | | | |
| Take a walk | | | |
| Defer hero task | | | |

#### Chosen because
- [ ] Lowest Executive Cost
- [ ] Highest goal alignment
- [ ] Behavior memory pattern
- [ ] Calendar constraint
- [ ] Other: ___

#### Outcome (record at T+6h or post-execution)
| Metric | Before | After | Δ |
|--------|--------|-------|---|
| User completed? | | Yes/No/Partial | |
| Stress (self-report 1–5) | | | |
| Energy (self-report 1–5) | | | |
| Regret? | | Yes/No | |

#### Dimension scores
| Dimension | Score | Notes |
|-----------|-------|-------|
| Executive Cost reduction | /5 | |
| Stress reduction | /5 | |
| Energy optimization | /5 | |
| Goal progress | /5 | |
| User satisfaction | /5 | |
| Regret avoided | /5 | |
| Confidence calibration | /5 | |
| Explainability | /5 | |
| **DQS** | **/5.0** | |

#### Verdict
- [ ] Correct decision (DQS ≥ 4.0)
- [ ] Suboptimal → file brain-decision
- [ ] Wrong decision → file [brain-bugs.md](brain-bugs.md)

#### Code references
- `DecisionEngine.decide` / `SimulationEngine.simulate`
- Brain Inspector trace ID: __
```

---

## Worked example (from product spec)

| Field | Value |
|-------|-------|
| **Decision** | Workout |
| **Alternatives** | Sleep, Continue coding, Take a walk |
| **Chosen because** | Lowest Executive Cost (system simulation) |
| **Outcome after 6h** | User completed workout |
| **Stress** | ↓ 23% |
| **Energy** | ↑ 18% |
| **Correct decision?** | **YES** (DQS 4.3) |

**Counter-example (brain-bug candidate):**

| Field | Value |
|-------|-------|
| **Decision** | 90-minute deep work |
| **Context** | 4h 52m sleep, overloaded calendar |
| **Alternatives** | 20-min recovery walk (Exec Cost 18 vs 54) |
| **Outcome** | User abandoned at 12 min; stress ↑ |
| **Correct decision?** | **NO** → Brain Issue #12 in [brain-bugs.md](brain-bugs.md) |

---

## Test cases

### LO-DQ-001 — Post-decision outcome tracking

| Priority | P0 |
| Objective | Every P0 hero recommendation in staging has DQ-EVAL record within 24h |
| Pass | ≥80% of samples DQS ≥ 3.5 in weekly audit |

### LO-DQ-002 — Alternative enumeration completeness

| Priority | P0 |
| Objective | Brain Inspector shows ≥2 alternatives in `PlanSimulation` when energy < 0.45 |
| Code | `SimulationEngine.simulate` |
| Pass | Simulation B present in trace |

### LO-DQ-003 — Wrong decision does not ship silently

| Priority | P0 |
| Objective | DQS < 2.0 triggers brain-bug entry before release |
| Pass | brain-bugs.md reviewed in release gate |

### LO-DQ-004 — Explainability without opening Inspector

| Priority | P1 |
| Objective | Hero why-now line sufficient for 3-second test |
| Pass | Human eval "Clear" ≥ 4.0 ([20-human-evaluation-protocol.md](20-human-evaluation-protocol.md)) |

### LO-DQ-005 — Goal alignment spot check

| Priority | P1 |
| Objective | Hero task maps to life model priority or urgent deadline |
| Pass | Manual audit 10 samples/week |

---

## Sampling protocol

| Release phase | Sample size | Who scores |
|---------------|-------------|------------|
| Weekly staging | 20 decisions | QA + 1 product |
| Pre-release | 50 decisions | QA + Product + Eng |
| Post-release | 10/day first week | On-call + weekly rollup |

**Stratified sampling:** Include low sleep, high calendar, cycle luteal, medication due, and "all green" days equally.

---

## Integration with release process

Add to [12-release-checklist.md](12-release-checklist.md):

- [ ] Weekly DQS average ≥ **3.8** on staging sample
- [ ] Zero open **P0 brain-bugs** (wrong decision with health/safety impact)
- [ ] brain-bugs.md reviewed; fixed issues linked to version

Add to [14-production-readiness.md](14-production-readiness.md): Decision Quality sub-score (see updated doc).

---

## Metrics dashboard (target)

Track over time — not just bugs:

| Metric | Target |
|--------|--------|
| Mean DQS | ≥ 4.0 |
| % decisions DQS ≥ 4.0 | ≥ 70% |
| Regret rate (user reported) | < 15% |
| Brain-bug recurrence (same root cause) | 0 |
| Human "Would I follow it?" yes rate | ≥ 65% |

---

## Anti-patterns (do not optimize for)

- Hero always = highest priority task (ignores energy)
- Hero always = easiest task (ignores goals)
- LLM copy overrides brain intent without mutation audit
- 100% completion rate on wrong tasks (busy, not meaningful)

**North star remains:** Meaningful tasks completed per week — Decision Quality is the leading indicator.
