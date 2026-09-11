# LifeOS Quality Validation Framework

**Version:** 1.1  
**Product:** LifeOS / FlowOS — AI-powered executive function OS for Apple platforms  
**Status:** Production-readiness + decision-quality validation suite  
**Last updated:** August 2026

---

## Purpose

This folder contains the complete Quality Validation Framework for LifeOS. A dedicated QA team can execute validation **without additional clarification** using these documents, existing unit tests, and the manual test case templates provided.

**North-star product metric:** Meaningful tasks completed per week (not screen time).

**Related docs:**

- [full-app-improvement-program.md](full-app-improvement-program.md) — whole-app improvement status (Q1–Q4 waves + canvas)
- [ATTENTION_OS_SPEC.md](../ATTENTION_OS_SPEC.md) — product vision, UX strategy, accessibility
- [build-and-test.md](../build-and-test.md) — automation commands
- [architecture/dependencies.md](../architecture/dependencies.md) — package graph

---

## Document Index

| # | Document | Description |
|---|----------|-------------|
| — | [README.md](README.md) | This index, conventions, execution order |
| 1 | [01-test-strategy.md](01-test-strategy.md) | Mission, scope, personas, environments, tooling |
| 2 | [02-test-matrix.md](02-test-matrix.md) | 18 features × 12 dimensions (216 cells) |
| 3 | [03-module-test-cases.md](03-module-test-cases.md) | Package-level test cases (Core, AI, Data, Features, Health, Brain) |
| 4 | [04-screen-test-cases.md](04-screen-test-cases.md) | Per-screen specs (45+ surfaces) + screen test cases |
| 5 | [05-flow-test-cases.md](05-flow-test-cases.md) | 22 end-to-end flows with interruption variants |
| 6 | [06-edge-cases.md](06-edge-cases.md) | Data, permission, network, device-state matrix |
| — | [timeline-feature-audit.md](timeline-feature-audit.md) | Today timeline source of truth, NOW marker, overlap, meal physics |
| — | [timeline-complete-fix-plan.md](timeline-complete-fix-plan.md) | Full fix plan T-01–T-37 including clock rail, cloud merge, briefing NOW |
| — | [ios26-revamp-plan.md](ios26-revamp-plan.md) | **QA-IOS26-01** — migrate to iOS 26 / macOS 26, Liquid Glass chrome, motion language, testing plan |
| — | [full-app-improvement-program.md](full-app-improvement-program.md) | Living whole-app backlog status (Q1–Q4, persistence, architecture, a11y, fake-glass) |
| — | [ux-agent-screenshot-pipeline.md](ux-agent-screenshot-pipeline.md) | UI tests → `screenshots/ux-agent/` → Cursor UI/UX agent review |
| 7 | [07-ai-validation.md](07-ai-validation.md) | GLM/LLM evaluation rubric and golden datasets |
| 8 | [08-executive-brain-validation.md](08-executive-brain-validation.md) | Deterministic brain + FlowDirector validation |
| 9 | [09-performance-benchmarks.md](09-performance-benchmarks.md) | Targets, measurement protocol, Instruments |
| 10 | [10-accessibility-checklist.md](10-accessibility-checklist.md) | VoiceOver, Dynamic Type, Reduce Motion, per-screen |
| 11 | [11-regression-suite.md](11-regression-suite.md) | Tier 1–4 regression mapped to 54 unit test files |
| 12 | [12-release-checklist.md](12-release-checklist.md) | Pre-release gate checklist |
| 13 | [13-risk-assessment.md](13-risk-assessment.md) | FMEA-style risk register |
| 14 | [14-production-readiness.md](14-production-readiness.md) | Scoring model, sign-off criteria |
| 15 | [15-decision-quality-framework.md](15-decision-quality-framework.md) | **Was this the best decision?** — DQS scoring |
| 16 | [16-learning-validation.md](16-learning-validation.md) | Behavior memory adaptation over weeks |
| 17 | [17-digital-twin-validation.md](17-digital-twin-validation.md) | Same calendar, different twin → different rec |
| 18 | [18-ai-hallucination-audit.md](18-ai-hallucination-audit.md) | P0 fabrication audit (meds, health, calendar) |
| 19 | [19-executive-cost-validation.md](19-executive-cost-validation.md) | Optimization function / burden comparison |
| 20 | [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md) | Human HRS ratings — ground truth dataset |
| — | [brain-bugs.md](brain-bugs.md) | Decision mistakes log (`brain-decision` label) |
| 21 | [21-life-simulator.md](21-life-simulator.md) | Synthetic virtual human, 30/365-day simulation |
| 22 | [22-decision-regression.md](22-decision-regression.md) | Golden brain decisions — **CI-blocking** |
| 23 | [23-ui-intelligence.md](23-ui-intelligence.md) | Cognitive load metrics per screen |
| 24 | [24-autonomous-actions.md](24-autonomous-actions.md) | Schedule mutation consistency |
| 25 | [25-goal-graph-validation.md](25-goal-graph-validation.md) | Task → Project → Mission → Goal |
| 26 | [26-trust-validation.md](26-trust-validation.md) | Trust score 0–100 per recommendation |
| 27 | [27-reality-replay.md](27-reality-replay.md) | **Reality Replay** — real past week vs brain versions |
| 28 | [28-counterfactual-engine.md](28-counterfactual-engine.md) | Plan A/B/C counterfactuals |
| 29 | [29-confidence-calibration.md](29-confidence-calibration.md) | Confidence vs outcome calibration |
| 30 | [30-explainability-validation.md](30-explainability-validation.md) | Signals ↔ explanation alignment |
| 31 | [31-memory-drift-validation.md](31-memory-drift-validation.md) | Compressed memory fidelity |
| 32 | [32-goal-stability.md](32-goal-stability.md) | Goal graph migration |
| 33 | [33-autonomy-budget.md](33-autonomy-budget.md) | Autonomy levels 0–4 |
| 34 | [34-human-satisfaction.md](34-human-satisfaction.md) | Accepted / ignored / dismissed / modified |
| 35 | [35-ai-cost-validation.md](35-ai-cost-validation.md) | AI token and cost regression |
| 36 | [36-failure-recovery.md](36-failure-recovery.md) | Intentional failure injection |
| 37 | [37-ui-lag-fix-scorecard.md](37-ui-lag-fix-scorecard.md) | **UI lag fixes** — scenarios, scores ≥70 pass, run commands |

**Fixtures:** [fixtures/ai/](fixtures/ai/), [fixtures/decisions/](fixtures/decisions/), [fixtures/replay/](fixtures/replay/), [fixtures/simulator/](fixtures/simulator/), [fixtures/counterfactual/](fixtures/counterfactual/), [fixtures/autonomous/](fixtures/autonomous/), [fixtures/learning/](fixtures/learning/), [fixtures/twin/](fixtures/twin/), [fixtures/hallucination/](fixtures/hallucination/) — no secrets committed.

---

## Executive Validation Platform (EVP)

The **Executive Validation Platform** automates compliance with this QA contract. It parses `Documentation/qa/*.md` — it never duplicates test cases in code.

**North-star question:** *Would this Executive Brain make better decisions for a real person over 30 days than the previous version?*

### Quick start

```bash
./evp index              # Parse docs 01–36 → RTM (Documentation/qa/.engine/)
./evp run --tier 2       # Static + functional (package tests)
./evp decisions          # Decision regression — CI-blocking
./evp replay --fixture REPLAY-001
./evp release            # Release gate
./evp readiness          # Production readiness score
./evp compare-versions v1.0.0 v1.1.0
./evp trace BRAIN-DEC-001
```

`./quality` is a backward-compatible alias for `./evp`.

**Package:** [`Tools/ExecutiveValidationPlatform/`](../Tools/ExecutiveValidationPlatform/)  
**Generated artifacts:** `Documentation/qa/.engine/` (gitignored) — `rtm.json`, `dashboard.html`, `junit.xml`, `version-comparison.json`

### Validation pyramid

| Layer | Name | Primary docs |
|-------|------|--------------|
| L1 | Static | 01, 02 |
| L2 | Functional | 03–05, 11–12 |
| L3 | Decision | **22**, 08, 15 |
| L4-R | Reality Replay | **27** |
| L4-S | Synthetic Simulation | 21, 17, 36 |
| L5 | Learning | 16, 31 |
| L6 | Executive Cost | 19, 28, 35 |
| L7 | Trust | 26, 20, 29, 34 |

---

## Test ID Convention

```
LO-{MODULE}-{CATEGORY}-{NNN}
```

### Modules

| Code | Scope |
|------|-------|
| `CORE` | LookAfterCore package |
| `DATA` | LookAfterData package |
| `AI` | LookAfterAI package (GLM, prompts, FlowDirector) |
| `BRAIN` | ExecutiveBrain package |
| `FEAT` | LookAfterFeatures ViewModels |
| `IOS` | LookAfter-iOS app UI |
| `MAC` | LookAfter-macOS app |
| `WGT` | Widget + Live Activity |
| `FLOW` | End-to-end user flows |

### Categories

| Code | Dimension |
|------|-----------|
| `FN` | Functional |
| `UX` | UX / 3-second test |
| `AI` | AI intelligence |
| `PERF` | Performance |
| `A11Y` | Accessibility |
| `SEC` | Security |
| `REL` | Reliability / recovery |
| `DATA` | Data integrity |
| `DQ` | Decision quality |
| `LEARN` | Learning / behavior adaptation |
| `TWIN` | Digital twin |
| `HALL` | Hallucination / fabrication |
| `COST` | Executive Cost |
| `HUM` | Human evaluation |

### Flow IDs

End-to-end flows use `FLOW-NNN` (see [05-flow-test-cases.md](05-flow-test-cases.md)).

---

## Priority & Severity

### Priority (test execution order)

| Level | Definition |
|-------|------------|
| **P0** | Ship blocker — must pass before any release |
| **P1** | Release candidate — must pass before App Store / TestFlight GA |
| **P2** | Post-release — schedule within first sprint after launch |
| **P3** | Nice-to-have — backlog |

### Severity (defect classification)

| Level | Definition | Example |
|-------|------------|---------|
| **S1** | Critical — data loss, crash, wrong medical/health guidance, auth bypass | Hero shows completed task; cycle day off by >7 days |
| **S2** | Major — core feature broken, no workaround | Planning mutations fail silently |
| **S3** | Minor — workaround exists | Badge count stale on module tile |
| **S4** | Cosmetic — visual polish | 2pt misalignment on card |

---

## Test Case Template (22 fields)

Every documented test case includes:

| Field | Description |
|-------|-------------|
| Test ID | `LO-{MODULE}-{CATEGORY}-{NNN}` |
| Priority | P0–P3 |
| Severity | S1–S4 |
| Feature | Product feature area |
| Module | Package or app target |
| Scenario | Short name |
| Test Objective | What is being verified |
| Preconditions | Required state before steps |
| Steps | Numbered actions |
| Expected Result | Pass criteria |
| Actual Result | *(filled during execution)* |
| Pass / Fail | *(filled during execution)* |
| Performance Target | Latency / fps / memory if applicable |
| Data Validation | Persistence, sync, schema checks |
| UI Validation | Visual / layout checks |
| Accessibility Validation | VoiceOver, Dynamic Type, etc. |
| AI Validation | Grounding, safety, schema (if applicable) |
| Regression Risk | Related areas that may break |
| Notes | Fixtures, device requirements |

---

## Screen Spec Template (15 fields)

Every screen in [04-screen-test-cases.md](04-screen-test-cases.md) includes:

1. Purpose  
2. User Goal  
3. Dependencies  
4. Entry Points  
5. Exit Points  
6. Expected Brain Behaviour  
7. Expected AI Behaviour  
8. Expected UI Behaviour  
9. Animations  
10. Data Sources  
11. Performance Targets  
12. Accessibility Requirements  
13. Failure States  
14. Recovery Behaviour  
15. Analytics Events / Regression Risks  

---

## Execution Order

### Phase 1 — Automated baseline (~30 min)

```bash
cd Packages/LookAfterCore && swift test
cd Packages/ExecutiveBrain && swift test
cd Packages/LookAfterData && swift test
cd Packages/LookAfterFeatures && swift test
cd Packages/LookAfterAI && swift test
cd Packages/LookAfterHealth && swift test
```

See [11-regression-suite.md](11-regression-suite.md) Tier 1–2.

### Phase 2 — P0 manual smoke (~45 min)

Execute FLOW-001 through FLOW-010 from [05-flow-test-cases.md](05-flow-test-cases.md).

### Phase 3 — P0 test cases (~1 day)

All P0 cases in modules, screens, AI, and brain docs.

### Phase 4 — Full regression (~3 days)

P1 cases, edge matrix, accessibility pass, performance benchmarks.

### Phase 5 — Release gate

[12-release-checklist.md](12-release-checklist.md) + [14-production-readiness.md](14-production-readiness.md) sign-off.

### Phase 6 — Decision quality moat (ongoing)

1. Sample 20+ decisions/week → [15-decision-quality-framework.md](15-decision-quality-framework.md) DQS  
2. Human ratings → [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md) HRS  
3. File wrong decisions → [brain-bugs.md](brain-bugs.md) (not generic bugs)  
4. Run LO-LEARN-001, LO-TWIN-001, LO-COST-001, red-team LO-HALL-* each release  

**Traditional QA validates behavior. Phase 6 validates life improvement.**

---

## Validation Dimensions

Every feature must be validated from:

- Functional  
- Visual  
- UX (3-second test: Where am I? What should I do? Why? What happens on tap?)  
- Accessibility  
- Performance  
- Reliability  
- Data Integrity  
- AI Intelligence  
- Offline Behaviour  
- Recovery  
- Security  
- Regression  
- **Decision quality** ([15-decision-quality-framework.md](15-decision-quality-framework.md))  
- **Learning** ([16-learning-validation.md](16-learning-validation.md))  
- **Fabrication-free AI** ([18-ai-hallucination-audit.md](18-ai-hallucination-audit.md))  

---

## Brain bugs vs software bugs

| | Software bug | Brain bug |
|---|--------------|-----------|
| **Example** | Crash on hero tap | 90min deep work after 4h sleep |
| **Tracker** | Issue tracker | [brain-bugs.md](brain-bugs.md) |
| **Label** | `bug` | `brain-decision` |
| **Pass functional QA?** | No | **Yes — still wrong** |

---

## Known Gaps (baseline)

| Gap | Mitigation |
|-----|------------|
| Zero XCUITest / UI automation | Manual + snapshot testing; Tier 3 smoke flows |
| No dedicated AI eval CI | Golden fixtures in `fixtures/ai/`; manual rubric scoring |
| macOS limited test coverage | Manual MAC-* cases in module doc |
| Widget tests minimal | Manual WGT-* cases |
| Decision quality not in CI | Phase 6 manual DQS + HRS; brain-bugs review at release |
| Learning/twin accelerated fixtures | Manual injection; 3-week LEARN-001 optional live soak |

**Estimated pre-framework readiness:** ~52/100 — see [14-production-readiness.md](14-production-readiness.md).  
**With Phase 6 executed on staging:** target **≥85/100** including Decision Quality sub-score.
