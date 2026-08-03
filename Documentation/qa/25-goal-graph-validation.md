# 25. Goal Graph Validation

**Document ID:** QA-25  
**Validation Layer:** Cross-cutting  
**Parent:** [README.md](README.md)

Validates Task → Project → Mission → Goal hierarchy via [`LifeModelStore`](../../Packages/LookAfterCore/Sources/LookAfterCore/Profile/LifeModelStore.swift).

---

## Hierarchy Rule

```
Task → Project → Mission → Goal
```

If chain breaks, recommendation must **not** reach UI unless explicit orphan policy applies.

---

## Test Cases

### GOAL-001 — Valid chain reaches hero

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | Task linked through full chain |
| Expected | Hero shows task; inspector shows goal path |

### GOAL-002 — Orphan task blocked

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | Task with no Project |
| Expected | Task excluded from hero candidates |

### GOAL-003 — Mission without goal blocked

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Descendant tasks not hero-eligible |

---

## Cross-links

- [32-goal-stability.md](32-goal-stability.md) — migration when goals evolve
