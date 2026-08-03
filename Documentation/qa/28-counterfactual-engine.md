# 28. Counterfactual Engine Validation

**Document ID:** QA-28  
**Validation Layer:** L6  
**Parent:** [README.md](README.md)

Every decision automatically generates alternatives (Plan A/B/C). Compare expected vs actual Executive Cost.

---

## Data Model

Leverages [`SimulationEngine.simulate`](../../Packages/ExecutiveBrain/Sources/ExecutiveBrain/Engine/SimulationEngine.swift):

| Field | Source |
|-------|--------|
| Chosen plan | `decision.intent` |
| Plan A / B / C | `decision.simulations[]` |
| Expected cost | `projectedCost.totalBurden` |
| Actual cost | Post-outcome (replay or sim) |
| Better plan existed? | `min(alternatives.cost) < chosen.cost` |

---

## Test Cases

### CF-001 — Alternatives generated

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | ≥2 simulations for low-energy + multi-task world |
| Fixture | `fixtures/counterfactual/cf_001.json` |

### CF-002 — Missed opportunity detection

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | When alt B has lower totalBurden than chosen, flag `missedOpportunity: true` |

### CF-003 — Learning signal export

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Counterfactual summary written to `.engine/counterfactuals.json` |

---

## CLI

`./evp counterfactual CF-001`
