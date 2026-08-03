# 32. Goal Stability Validation

**Document ID:** QA-32  
**Validation Layer:** Cross-cutting  
**Parent:** [README.md](README.md)

Validate Goal Graph remains consistent when goals evolve (e.g. lose weight → marathon).

---

## Migration Scenario

```
Goal: Lose weight → Gym, Diet, Sleep tasks
↓ User adds: Marathon
↓ Migration: old tasks remap or archive correctly
```

---

## Test Cases

### GSTAB-001 — Weight loss → marathon migration

| Field | Value |
|-------|-------|
| Priority | P0 |
| Steps | Add Marathon goal; migrate Gym task to new Mission |
| Expected | No orphan tasks; hero traceable to Marathon Mission |
| Fail | Gym task shows with no goal path |

### GSTAB-002 — Archived goal tasks hidden

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Tasks under archived goal not hero-eligible |

### GSTAB-003 — Dual active goals coexist

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Both goals' tasks eligible; priority ordering respected |

---

## Cross-links

- [25-goal-graph-validation.md](25-goal-graph-validation.md)
