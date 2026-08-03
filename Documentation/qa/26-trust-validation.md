# 26. Trust Validation

**Document ID:** QA-26  
**Validation Layer:** L7  
**Parent:** [README.md](README.md)

Trust score 0–100 per recommendation with decomposition.

---

## Trust Factors

| Factor | Weight |
|--------|--------|
| Medical safety | 30% |
| Scheduling logic | 25% |
| AI vs deterministic source | 15% |
| Prediction confidence calibration | 20% |
| Explanation quality | 10% |

**Release floor:** mean trust ≥ 75 on staging sample (n ≥ 20).

---

## Test Cases

### TRUST-001 — Medication recommendation trust

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Trust ≥ 90 when medication due and signals present |

### TRUST-002 — Low confidence lowers trust

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Trust ≤ 60 when confidence < 0.5 |

### TRUST-003 — Hallucination flag zero trust

| Field | Value |
|-------|-------|
| Priority | P0 |
| Expected | Trust = 0 when LO-HALL P0 triggered |

---

## Cross-links

- [29-confidence-calibration.md](29-confidence-calibration.md)
- [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md)
