# 27. Reality Replay Validation

**Document ID:** QA-27  
**Validation Layer:** L4-R  
**Priority:** HIGHEST  
**Parent:** [README.md](README.md)

Replay the user's **real past week** (anonymized) — compare what actually happened vs Brain vN vs Brain vN+1.

---

## Purpose

Benchmark improvements against **real life**, not only synthetic fixtures. Answers: *Would the new brain have produced a better outcome?*

---

## Export Schema

Fixtures in [`fixtures/replay/`](fixtures/replay/) — **never live PII in git**.

```json
{
  "id": "REPLAY-001",
  "weekStart": "2026-07-21",
  "decisionPoints": [
    {
      "timestamp": "2026-07-21T09:00:00Z",
      "inputSnapshot": { },
      "actualOutcome": {
        "completed": false,
        "stressLevel": 7,
        "executiveCostActual": 85
      }
    }
  ]
}
```

---

## Test Cases

### REPLAY-001 — Anonymized week smoke

| Field | Value |
|-------|-------|
| Priority | P0 |
| Validation Layer | L4-R |
| Steps | `./evp replay --fixture REPLAY-001` |
| Expected | All decision points evaluated; comparison report generated |
| Phase 1 | Schema validation + stub runner |

### REPLAY-002 — Meeting moved Monday

| Field | Value |
|-------|-------|
| Priority | P0 |
| Scenario | Monday meeting moved; compare actual vs brain counterfactual |
| Expected | Report shows whether Brain v2 would have rescheduled workout better |

### REPLAY-003 — Version comparison

| Field | Value |
|-------|-------|
| Priority | P0 |
| Steps | `./evp replay --compare v1.0.0 v1.1.0 --fixture REPLAY-001` |
| Expected | Per-point verdict: better / same / worse vs previous version |

---

## Privacy Rules

1. Strip names, addresses, exact locations before export
2. Hash stable IDs for tasks/events
3. Replay fixtures reviewed before commit

---

## North-star Integration

Feeds `./evp compare-versions` evidence: `realityReplayWeeks`, `betterOutcomesPct`.
