# 33. Autonomy Budget Validation

**Document ID:** QA-33  
**Validation Layer:** Cross-cutting  
**Parent:** [README.md](README.md)

Verify the Brain never exceeds its granted autonomy level.

---

## Autonomy Levels

| Level | Allowed actions |
|-------|-----------------|
| 0 | Suggest only |
| 1 | Reschedule reminders |
| 2 | Move tasks |
| 3 | Mutate calendar |
| 4 | Book travel (future) |

---

## Test Cases

### AUTO-LVL-001 — Level 0 suggest only

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | autonomyLevel = 0 |
| Expected | No calendar writes, no task mutations |
| Fail | Level 0 brain writes calendar event |

### AUTO-LVL-002 — Level 2 moves tasks only

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Task reschedule OK; calendar unchanged |

### AUTO-LVL-003 — Level 3 calendar mutation

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Calendar block moves allowed |

---

## Cross-links

- [24-autonomous-actions.md](24-autonomous-actions.md)
