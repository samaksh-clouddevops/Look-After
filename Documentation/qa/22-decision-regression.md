# 22. Decision Regression Testing

**Document ID:** QA-22  
**Validation Layer:** L3  
**Parent:** [README.md](README.md)

Golden brain decisions — input fixture → expected intent semantics. **CI-blocking** on any `BRAIN-DEC-*` failure.

---

## Purpose

Every brain change must preserve or improve documented decision quality. Fixtures live in [`fixtures/decisions/`](fixtures/decisions/) — never invented in Swift.

---

## Fixture Schema

```json
{
  "id": "BRAIN-DEC-NNN",
  "sourceDocument": "Documentation/qa/22-decision-regression.md",
  "input": { "sleepHours": 5, "tasks": [...], "now": "2026-08-01T08:30:00Z" },
  "expectedDecision": {
    "intentContains": ["OAuth"],
    "mustNotRecommend": ["Take thyroid now"],
    "conclusionsContainAny": ["small", "light"]
  },
  "minMatchScore": 0.85
}
```

---

## Test Cases

### BRAIN-DEC-001 — Low sleep defers deep work

| Field | Value |
|-------|-------|
| Priority | P0 |
| Validation Layer | L3 |
| Preconditions | 5h sleep, 45min free block, 90min task |
| Expected | Intent or conclusions favor light work / medication; no "this evening" deep work |
| Fixture | `fixtures/decisions/brain_dec_001.json` |
| Automated | DecisionRegressionRunner |

### BRAIN-DEC-002 — Medication window honored

| Field | Value |
|-------|-------|
| Priority | P0 |
| Validation Layer | L3 |
| Preconditions | Vitamin D due at 09:00, now 09:10 |
| Expected | Day plan includes medication block |
| Fixture | `fixtures/decisions/brain_dec_002.json` |

### BRAIN-DEC-052 — OAuth deadline over gym with poor sleep

| Field | Value |
|-------|-------|
| Priority | P0 |
| Validation Layer | L3 |
| Preconditions | 5h sleep, OAuth due tomorrow, gym + thyroid 07:30 scheduled |
| Expected | Intent references OAuth/deadline; must not push immediate thyroid when inappropriate |
| Fixture | `fixtures/decisions/brain_dec_052.json` |
| minMatchScore | 0.85 |

---

## CI Gate

- `./evp decisions` — **blocking** on PR when fixtures exist
- Any score below `minMatchScore` → fail Layer L3

---

## Cross-links

- [08-executive-brain-validation.md](08-executive-brain-validation.md) — pipeline audit
- [15-decision-quality-framework.md](15-decision-quality-framework.md) — DQS rubric
