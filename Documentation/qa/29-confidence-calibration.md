# 29. Confidence Calibration Validation

**Document ID:** QA-29  
**Validation Layer:** L7  
**Parent:** [README.md](README.md)

Measure brain confidence vs actual correctness — a trustworthy brain knows when it is unsure.

---

## Calibration Matrix

| Confidence | Outcome | Calibration |
|------------|---------|-------------|
| 98% | Wrong | **Poor** — overconfident |
| 42% | Wrong | **Good** — appropriate uncertainty |
| 85% | Correct | **Good** |
| 95% | Correct | **Acceptable** |

---

## Metrics

| Metric | Threshold |
|--------|-----------|
| Brier score | ≤ 0.25 |
| Overconfidence rate (conf>90, wrong) | ≤ 5% |
| Underconfidence rate (conf<50, correct) | ≤ 15% |

---

## Test Cases

### CAL-001 — Overconfidence flagged

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | Record confidence 0.98, outcome wrong |
| Expected | Calibration verdict: Poor |

### CAL-002 — Appropriate uncertainty

| Field | Value |
|-------|-------|
| Priority | P0 |
| Preconditions | confidence 0.42, outcome wrong |
| Expected | Calibration verdict: Good |

### CAL-003 — Calibration curve report

| Field | Value |
|-------|-------|
| Priority | P1 |
| Steps | `./evp calibrate` |
| Expected | Brier score + bucket chart in dashboard |

---

## CLI

`./evp calibrate`
