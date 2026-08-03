# 34. Human Satisfaction Validation

**Document ID:** QA-34  
**Validation Layer:** L7  
**Parent:** [README.md](README.md)

Measure whether the user would actually accept recommendations — not Executive Cost alone.

---

## Outcome Taxonomy

| Outcome | Learning signal |
|---------|-----------------|
| Accepted | +1.0 |
| Modified | +0.5 (capture edit delta) |
| Ignored | -0.3 |
| Dismissed | -1.0 |

---

## Test Cases

### SAT-001 — Accept rate baseline

| Field | Value |
|-------|-------|
| Priority | P1 |
| Metric | acceptRate ≥ 60% on staging (n ≥ 50) |

### SAT-002 — Dismissed after poor calibration

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | High-confidence dismissals flagged for review |

### SAT-003 — Satisfaction ingest

| Field | Value |
|-------|-------|
| Priority | P1 |
| Steps | `./evp satisfaction` |
| Expected | Reads CSV/telemetry → `.engine/satisfaction.json` |

---

## Cross-links

- [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md)

---

## CLI

`./evp satisfaction`
