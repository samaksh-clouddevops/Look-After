# 24. Autonomous Action Validation

**Document ID:** QA-24  
**Validation Layer:** Cross-cutting  
**Parent:** [README.md](README.md)

Schedule mutation consistency when the brain autonomously moves tasks, reminders, and calendar blocks.

---

## Test Cases

### AUTO-001 — Meeting moved → workout rescheduled

| Field | Value |
|-------|-------|
| Priority | P0 |
| Trigger | Meeting moved +2h |
| Expected | Workout, reminder, calendar block all moved consistently; no orphan events |
| Fixture | `fixtures/autonomous/auto_001.json` |

### AUTO-002 — Deadline slip propagates

| Field | Value |
|-------|-------|
| Priority | P1 |
| Trigger | OAuth deadline +1 day |
| Expected | Dependent prep tasks shift; hero reflects new urgency |

### AUTO-003 — Rollback on partial failure

| Field | Value |
|-------|-------|
| Priority | P0 |
| Trigger | Calendar write fails mid-mutation |
| Expected | No partial state; user message; tasks unchanged |

---

## Consistency Rules

1. Every moved entity references same `mutationBatchId`
2. Reminder fire time matches calendar block start ± tolerance
3. Hero intent updated within one brain tick after mutation

---

## Cross-links

- [33-autonomy-budget.md](33-autonomy-budget.md) — level enforcement
- [36-failure-recovery.md](36-failure-recovery.md) — calendar unavailable
