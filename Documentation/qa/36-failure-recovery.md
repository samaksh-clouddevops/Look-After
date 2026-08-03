# 36. Failure Recovery Validation

**Document ID:** QA-36  
**Validation Layer:** L4-S  
**Parent:** [README.md](README.md)

Life Simulator intentionally breaks dependencies — Executive Brain must degrade gracefully.

---

## Failure Matrix

| Failure injected | Expected degradation |
|------------------|------------------------|
| Calendar unavailable | Tasks-only timeline; no crash |
| HealthKit revoked | Capacity defaults; user message |
| AI timeout | Deterministic fallback |
| Corrupted memory | Reset + user message |
| Missing reminders | Graceful skip |
| Network offline | Queue; no partial mutations |
| Clock skew | Reject or clamp times |
| Duplicate events | Dedupe per merge rules |

---

## Test Cases

### FAIL-001 — Calendar unavailable

| Field | Value |
|-------|-------|
| Priority | P0 |
| Steps | `./evp simulate --fail FAIL-001` |
| Expected | Brain tick completes; tasks-only plan |
| Cross-ref | EDGE-* in [06-edge-cases.md](06-edge-cases.md) |

### FAIL-002 — HealthKit revoked

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Default energy; no crash |

### FAIL-003 — AI timeout

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Deterministic brain path still issues hero |

### FAIL-004 — Corrupted memory

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Memory reset; user notified |

### FAIL-005 — Network offline

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | No partial plan mutations |

### FAIL-006 — Clock skew

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Times clamped or rejected |

### FAIL-007 — Duplicate events

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Deduped timeline |

---

## CLI

`./evp simulate --fail FAIL-001`
