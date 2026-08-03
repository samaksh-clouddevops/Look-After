# 19. Executive Cost Validation

**Document ID:** QA-19  
**Parent:** [README.md](README.md)

Validates LifeOS's **optimization function itself** — not just that code runs.

**Code reference:** `ExecutiveCost`, `ExecutiveCostDelta` in `Packages/LookAfterCore/Sources/LookAfterCore/Executive/ExecutiveCost.swift`; projection in `SimulationEngine.projectCost`; scoring in `SimulationEngine.score`.

---

## Executive Cost model

### Burden components (`ExecutiveCost`)

| Field | Meaning (validation sign) |
|-------|---------------------------|
| `stress` | Cognitive/emotional load (+ burden) |
| `time` | Minutes committed (+ burden) |
| `money` | Financial cost (+ burden) |
| `energy` | Depletion (+ burden); negative delta = recovery |
| `attention` | Focus switching cost (+ burden) |
| `restartTax` | Cost to resume after interruption (+ burden) |
| `regret` | Anticipated regret (+ burden) |
| `opportunityCost` | Foregone alternatives (+ burden) |
| `relationshipCost` | Social/relationship impact (+ burden) |
| `healthCost` | Physical health impact (+ burden; recovery negative) |

**Total burden:**

```
totalBurden = stress + time + money + energy + attention + restartTax + regret
            + opportunityCost + relationshipCost + max(0, healthCost)
```

**Lower totalBurden = better option** (for same confidence level).

### Intent deltas (`ExecutiveCostDelta`)

Applied in `SimulationEngine.projectCost` from `intent.expectedCostReduction`:

- `stress`, `time`, `restartTax`, `energy`, `attention`

---

## Validation method

For each scenario:

1. **Enumerate alternatives** (minimum 2, including chosen)  
2. **Manual calculation** — human QA fills expected cost vector  
3. **System calculation** — read from Brain Inspector / `PlanSimulation.projectedCost`  
4. **Compare** — chosen option must match lowest burden (± tolerance)  
5. **Score** — `SimulationEngine.score` should rank same order  

**Tolerance:** ±5 points per field or ±10% totalBurden — document if engine uses heuristics not visible to QA.

---

## Worked example (product spec)

### Scenario: Low energy, coding in flow vs walk

| Option | stress | energy | restartTax | health | Other | **totalBurden** |
|--------|--------|--------|------------|--------|-------|-----------------|
| **Continue coding** | +20 | -10 | 0 | -15 | attention +10 | **54** |
| **Take walk** | -30 | +15 | +5 | +25 | time +15 | **18** |

**Correct choice:** Walk (lower burden)

| Field | Expected system behavior |
|-------|-------------------------|
| Chosen simulation | Walk or equivalent recovery intent |
| `wasChosen: true` | On lowest score in `PlanSimulation` array |
| Hero | Aligns with recovery when energy < threshold |

---

## Test scenarios

### LO-COST-001 — Low sleep → recovery beats deep work

| Priority | P0 |
| Context | Sleep 4h 52m, `currentEnergy < 0.45` |
| Alternatives | 90 min deep work vs 20 min walk |
| Manual | Deep work burden > walk |
| Pass | Brain chooses lower burden; see [brain-bugs.md](brain-bugs.md) #12 if fail |

### LO-COST-002 — In-flow restart tax

| Priority | P0 |
| Context | `world.isInFlowSession == true` |
| Expected | `restartTax` baseline 35 vs 15 not in flow |
| Pass | Switching hero mid-flow penalized |

### LO-COST-003 — Overloaded cognitive load

| Priority | P1 |
| Context | `world.cognitiveLoad == .overloaded` |
| Expected | Base stress 40 vs 20 normal |
| Pass | Lighter alternatives simulated |

### LO-COST-004 — Simulation B present when energy low

| Priority | P0 |
| Code | `SimulationEngine.simulate` else branch (rest semantics) |
| Pass | At least 2 simulations in trace |

### LO-COST-005 — Score ordering matches burden ordering

| Priority | P0 |
| Steps | For each tick, verify `score` monotonic with inverse burden |
| Formula | `score = max(0, (1 - totalBurden/200) * confidence)` |

### LO-COST-006 — Medication intent health weight

| Priority | P1 |
| Context | Medication due |
| Expected | Skipping med increases healthCost/regret |

### LO-COST-007 — Short task vs long when depleted

| Priority | P1 |
| Context | Low energy, 2 pending tasks (15 min vs 90 min) |
| Expected | Shorter task lower burden unless deadline forces long |

### LO-COST-008 — Manual vs system audit sheet

| Priority | P0 (release) |
| Procedure | 10 scenarios × 2 alternatives; 90% match within tolerance |

---

## Audit worksheet template

```markdown
### COST-AUDIT-{NNN}

**Scenario ID:** LO-COST-___
**Date:** ___
**Brain tick time:** ___

| Alternative | stress | time | energy | restartTax | health | attention | regret | **totalBurden** | **score (sys)** |
|-------------|--------|------|--------|------------|--------|-----------|--------|-----------------|-----------------|
| A (manual) | | | | | | | | | |
| A (system) | | | | | | | | | |
| B (manual) | | | | | | | | | |
| B (system) | | | | | | | | | |

**Expected winner:** ___
**System chosen:** ___
**Match:** ☐ Yes ☐ No

**Discrepancy notes:** ___
```

---

## Integration with Decision Quality

| Executive Cost result | Decision Quality impact |
|----------------------|---------------------------|
| Correct lowest burden | Executive Cost reduction dimension → 4–5 |
| Wrong choice, close scores | DQS 3.0–3.5 — tune weights |
| Wrong choice, large gap | DQS < 2.0 — brain-bug |

See [15-decision-quality-framework.md](15-decision-quality-framework.md).

---

## Known engine behaviors (for auditors)

From `SimulationEngine.projectCost`:

- Base stress: 40 if overloaded else 20  
- Base energy term: `(1 - currentEnergy) * 30`  
- Base restartTax: 35 in flow session else 15  
- Intent delta applied to stress, restartTax, time, energy, attention  

Auditors should replicate these baselines before marking mismatch.

---

## Automated test roadmap

| Test | Status |
|------|--------|
| Snapshot `projectCost` for fixture WorldState | Planned |
| Assert chosen simulation min burden | Planned |
| `ExecutiveBrainEngineTests` extend with cost ordering | Planned |

**Current:** Manual audit required for release ([12-release-checklist.md](12-release-checklist.md)).

---

## Release gate

- [ ] LO-COST-001, LO-COST-004, LO-COST-005 **PASS**  
- [ ] COST-AUDIT sample: ≥ 90% manual/system match  
- [ ] No open P0 cost-ordering brain-bugs  

---

## Cross-references

- [08-executive-brain-validation.md](08-executive-brain-validation.md) — pipeline  
- [15-decision-quality-framework.md](15-decision-quality-framework.md) — outcome scoring  
- [17-digital-twin-validation.md](17-digital-twin-validation.md) — same calendar, different cost profiles
