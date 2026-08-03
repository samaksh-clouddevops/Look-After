# 14. Production Readiness

**Document ID:** QA-14  
**Parent:** [README.md](README.md)

Production readiness scoring model, sign-off criteria, and current baseline assessment.

---

## Scoring Model (100 points)

| Dimension | Weight | Scoring method |
|-----------|--------|----------------|
| **Functional completeness** | 22 | P0 pass rate × 22 |
| **AI / Brain quality** | 18 | Rubric avg / 5 × 18 |
| **Decision quality (DQS)** | 10 | Mean DQS / 5 × 10 — [15-decision-quality-framework.md](15-decision-quality-framework.md) |
| **Human evaluation (HRS)** | 5 | Mean HRS / 5 × 5 — [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md) |
| **Performance** | 13 | Benchmarks pass ratio × 13 |
| **Accessibility** | 8 | A11y P0 pass rate × 8 |
| **Security & privacy** | 8 | SEC P0 pass rate × 8 |
| **Reliability & recovery** | 8 | P0 flow + edge recovery pass × 8 |
| **Test automation coverage** | 4 | Automated / total P0 cases × 4 |
| **Documentation & runbooks** | 4 | Checklist complete × 4 |

**Minimum for release:** **85 / 100**

**Decision quality hard gates (in addition to score):**

- Zero open **Critical** entries in [brain-bugs.md](brain-bugs.md)  
- Zero **P0 hallucinations** in latest red-team ([18-ai-hallucination-audit.md](18-ai-hallucination-audit.md))  
- Mean **DQS ≥ 3.8** on staging sample (n ≥ 50)  
- Mean **HRS ≥ 3.8** ([20-human-evaluation-protocol.md](20-human-evaluation-protocol.md))

---

## Dimension Rubrics

### Functional completeness (22 pts)

```
Score = (P0_passed / P0_total) × 22
```

- P0_total ≈ 45 cases ([03-module-test-cases.md](03-module-test-cases.md), [04-screen-test-cases.md](04-screen-test-cases.md), [05-flow-test-cases.md](05-flow-test-cases.md))
- **Must be 100%** for release (22/22)

### Decision quality (10 pts)

```
Score = (mean_DQS / 5.0) × 10
```

- Sample n ≥ 50 decisions on staging per [15-decision-quality-framework.md](15-decision-quality-framework.md)
- **Minimum mean DQS:** 3.8 (below → cap this dimension at 6/10)

### Human evaluation (5 pts)

```
Score = (mean_HRS / 5.0) × 5
```

- From [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md)
- Follow-through rate ≥ 60% required for full points

### AI / Brain quality (18 pts)

```
Score = ((AI_safety_avg + AI_grounding_avg + Brain_audit_pass_rate) / 3) / 5 × 18
```

- AI_safety_avg, AI_grounding_avg from golden set ([07-ai-validation.md](07-ai-validation.md))
- Brain_audit_pass_rate = passed BRAIN-FIX fixtures / 8
- **Minimum averages:** safety ≥ 4.0, grounding ≥ 4.0

### Performance (15 pts)

```
Score = (benchmarks_passed / benchmarks_total) × 15
```

- 12 benchmarks in [09-performance-benchmarks.md](09-performance-benchmarks.md)
- Within 10% tolerance counts as pass

### Accessibility (10 pts)

```
Score = (A11Y_P0_passed / A11Y_P0_total) × 10
```

- ~8 P0 cases in [10-accessibility-checklist.md](10-accessibility-checklist.md)

### Security & privacy (10 pts)

```
Score = (SEC_P0_passed / SEC_P0_total) × 10
```

- 7 SEC cases in [03-module-test-cases.md](03-module-test-cases.md)

### Reliability & recovery (10 pts)

```
Score = (recovery_scenarios_passed / recovery_scenarios_total) × 10
```

- P0 flows + INT-A through INT-E variants
- Edge cases EDGE-N*, EDGE-P* critical subset

### Test automation coverage (5 pts)

```
Score = (automated_P0 / P0_total) × 5
```

- Current automated P0 ≈ 22 / 45 → ~2.4 / 5

### Documentation & runbooks (4 pts)

| Item | Points |
|------|--------|
| QA framework complete (incl. docs 15–20) | 2 |
| Release checklist executed | 1 |
| build-and-test.md accurate | 1 |

---

## Current Baseline Assessment (pre-framework execution)

**Estimated score: ~52 / 100**

| Dimension | Est. score | Notes |
|-----------|------------|-------|
| Functional completeness | 16 / 22 | Strong unit tests; UI P0 manual unverified |
| AI / Brain quality | 11 / 18 | Unit tests pass; no golden eval run |
| Decision quality (DQS) | 0 / 10 | Framework added; no staging samples yet |
| Human evaluation (HRS) | 0 / 5 | Protocol added; no ratings collected |
| Performance | 5 / 13 | No formal benchmark log |
| Accessibility | 2 / 8 | Not systematically tested |
| Security & privacy | 5 / 8 | Keychain tests pass; manual audit pending |
| Reliability & recovery | 4 / 8 | Integration tests partial |
| Test automation | 2 / 4 | 54 unit files; no XCUITest |
| Documentation | 4 / 4 | Framework complete incl. Phase 6 moat docs |

**Estimated score today:** ~49 / 100 (decision-quality layer not yet executed)

**After Phase 1–5 only (no DQS/HRS):** ~52 / 100  
**Target with Phase 6 on staging:** **≥85 / 100**

---

## Sign-off Criteria

All must be true for **Ship** decision:

| # | Criterion | Evidence |
|---|-----------|----------|
| 1 | Overall score ≥ **85/100** | This document worksheet |
| 2 | Zero open **P0** defects | Issue tracker |
| 3 | Zero open **S1** defects | Issue tracker |
| 4 | P0 manual + automated pass **100%** | Test logs |
| 5 | Mean **DQS ≥ 3.8** (n ≥ 50) | [15-decision-quality-framework.md](15-decision-quality-framework.md) |
| 6 | Mean **HRS ≥ 3.8** | [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md) |
| 7 | AI safety ≥ **4.0/5.0** | [07-ai-validation.md](07-ai-validation.md) log |
| 8 | AI grounding ≥ **4.0/5.0** | Same |
| 9 | Zero open **Critical** [brain-bugs.md](brain-bugs.md) | Brain bugs log |
| 10 | LO-COST-001, LO-TWIN-001, LO-LEARN-001 pass | Moat validation |
| 11 | Performance within targets (10% tolerance) | [09-performance-benchmarks.md](09-performance-benchmarks.md) log |
| 12 | Tier 3 smoke flows pass | [11-regression-suite.md](11-regression-suite.md) |
| 13 | [12-release-checklist.md](12-release-checklist.md) complete | Signed checklist |
| 14 | TestFlight 48h soak complete | Crash-free ≥ 99% |
| 15 | QA Lead sign-off | Signature block |
| 16 | Eng Lead sign-off | Signature block |
| 17 | Product sign-off | Signature block |

---

## Production Readiness Worksheet

**Build:** _______________  
**Date:** _______________  
**Evaluator:** _______________

| Dimension | Weight | Raw score | Weighted |
|-----------|--------|-----------|----------|
| Functional | 22 | /22 | |
| AI / Brain | 18 | /18 | |
| Decision quality (DQS) | 10 | /10 | |
| Human eval (HRS) | 5 | /5 | |
| Performance | 13 | /13 | |
| Accessibility | 8 | /8 | |
| Security | 8 | /8 | |
| Reliability | 8 | /8 | |
| Automation | 4 | /4 | |
| Documentation | 4 | /4 | |
| **TOTAL** | **100** | | **/100** |

**Decision:** ☐ Ship (≥85)  ☐ Hold (<85)  ☐ Ship with waivers

---

## Waiver Policy

Waivers allowed only for:

- S3/S4 defects with Product approval  
- Performance on non-reference devices (document delta)  
- Accessibility P2 items with remediation plan within 30 days  

**Never waive:** S1 defects, AI safety < 4.0, SEC P0 failures, P0 functional failures.

---

## Improvement Roadmap (score → 90+)

| Initiative | Points gain | Timeline |
|------------|-------------|----------|
| Execute all P0 manual cases | +6 functional | Sprint 1 |
| AI golden eval on staging | +4 AI | Sprint 1 |
| **50 DQS + HRS samples** | **+15 decision/human** | Sprint 1 |
| Performance benchmark log | +4 perf | Sprint 1 |
| VoiceOver + Dynamic Type pass | +4 a11y | Sprint 2 |
| XCUITest for FLOW-001, 002 | +1 automation | Sprint 2 |
| CI Tier 1 on every PR | +1 reliability | Sprint 1 |
| Close Critical brain-bugs | Gate | Ongoing |

---

## Sign-off Record

| Role | Name | Signature | Date | Build |
|------|------|-----------|------|-------|
| QA Lead | | | | |
| Engineering Lead | | | | |
| Product Owner | | | | |

---

## Version History

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-08 | Initial framework and baseline |
