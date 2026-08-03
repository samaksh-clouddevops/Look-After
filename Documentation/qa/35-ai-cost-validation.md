# 35. AI Cost Validation

**Document ID:** QA-35  
**Validation Layer:** L6  
**Parent:** [README.md](README.md)

Dedicated layer for GLM/OpenRouter cost creep as prompts evolve.

---

## Metrics

| Metric | Source | Release threshold |
|--------|--------|-------------------|
| Tokens per feature | GLMUsageLogger | ≤ baseline + 10% |
| Latency p95 | Network traces | ≤ 15s planning |
| Cache hit rate | Analytics cache | ≥ 40% |
| Cost per recommendation | Aggregated logs | ≤ $0.002 |
| Cost per chat | Aggregated logs | ≤ $0.01 |
| Cost per weekly review | Aggregated logs | ≤ $0.05 |

---

## Test Cases

### AICOST-001 — Recommendation cost ceiling

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | costPerRecommendation ≤ threshold from table above |

### AICOST-002 — Token regression gate

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | PR does not increase tokens/recommendation >10% vs baseline |

### AICOST-003 — Cost audit report

| Field | Value |
|-------|-------|
| Priority | P1 |
| Steps | `./evp cost-audit` |
| Expected | Executive + AI cost sections in dashboard |

---

## Data Source

[`GLMUsageLogger`](../../Packages/LifeOSAI/Sources/LifeOSAI/Logging/GLMUsageLogger.swift)

---

## CLI

`./evp cost-audit`
