# 30. Explainability Validation

**Document ID:** QA-30  
**Validation Layer:** Cross-cutting  
**Parent:** [README.md](README.md)

Verify **why** — explanation must reference only signals that actually influenced the decision.

---

## Validation Flow

```
Signals in WorldState → Decision → Explanation text
                              ↓
                    Do they match?
```

**Rule:** Explanation may cite only signals present in `WorldState` / `ReasoningTrace` per [`ExplanationBuilder`](../../Packages/ExecutiveBrain/Sources/ExecutiveBrain/Engine/DecisionEngine.swift).

---

## Test Cases

### EXPL-001 — Sleep cited only when sleep signal present

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | No healthSummary.sleep data |
| Expected | Explanation must not mention "sleep" or "rested" |
| Fail example | "You're well rested" with no sleep signal |

### EXPL-002 — Medication cited when due

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | Medication due within window |
| Expected | Explanation references medication |

### EXPL-003 — No fabricated calendar events

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Explanation does not cite meetings absent from timelineItems |

---

## CLI

`./evp explain EXPL-001`
