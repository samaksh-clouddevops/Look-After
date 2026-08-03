# 31. Memory Drift Validation

**Document ID:** QA-31  
**Validation Layer:** L5  
**Parent:** [README.md](README.md)

Test whether compressed memories remain faithful to decision-critical information.

---

## Protocol

```
100 behavior events → compress/summarize (BehaviorMemory path)
→ Re-run brain tick with compressed memory only
→ Same decision as pre-compression?
```

**Fail:** Compression loses information that changes hero intent.

---

## Test Cases

### MEM-001 — Gym defer pattern preserved

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | 100 events with Tue gym skips |
| Expected | Post-compression brain still avoids Tue gym suggestion |
| Fixture | `fixtures/learning/gym_tuesday_skip.json` |

### MEM-002 — Medication adherence preserved

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Compression retains morning med window signal |

### MEM-003 — Decision parity score

| Field | Value |
|-------|-------|
| Priority | P0 |
| Metric | decisionParity ≥ 0.95 (same intent class pre/post) |

---

## Data Source

[`BehaviorMemoryStore`](../../Packages/LifeOSData/Sources/LifeOSData/Behavior/BehaviorMemoryStore.swift)

---

## CLI

`./evp memory-drift MEM-001`
