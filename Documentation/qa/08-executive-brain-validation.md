# 8. Executive Brain Validation

**Document ID:** QA-08  
**Parent:** [README.md](README.md)

Validation for the **deterministic** Executive Brain pipeline and FlowDirector orchestration. The LLM is explicitly **not** in the brain pipeline (`ExecutiveBrainEngine.swift`).

---

## Brain Pipeline

```
Signals → WorldStateBuilder → ReasoningEngine → DecisionEngine → PlanningEngine → ExplanationBuilder
                                              ↓
                                    DecisionHistoryStore
                                              ↓
                                         BrainState → UI
```

**Parallel path:** FlowDirector → environment fusion → behavior analysis → scheduling → briefing surface.

**Decision quality moat (docs 15–20):** Pipeline correctness is necessary but not sufficient. Also validate DQS, learning, twin differentiation, Executive Cost ordering, and hallucination-free outputs — see [Moat validation cross-links](#moat-validation-cross-links) below.

---

## 12 Brain Audit Questions

For **every recommendation**, verify:

| # | Question | Evidence source |
|---|----------|-----------------|
| 1 | **Why this recommendation?** | `ExplanationBuilder`, BrainInspector trace |
| 2 | **Why now?** | `whyNowReasons` on hero; time signals |
| 3 | **What signals were used?** | `WorldState` fields (health, calendar, tasks, cycle) |
| 4 | **Which intentions were chosen?** | `decision.intent` enum |
| 5 | **Executive cost calculation** | Reasoning trace cost fields |
| 6 | **Prediction quality** | Flow prediction vs actual completion (behavior memory) |
| 7 | **Simulation quality** | `decision.simulations` count and diversity |
| 8 | **Goal alignment** | Match to `userKeyGoals` / life model priorities |
| 9 | **LifeState alignment** | Life model windows respected |
| 10 | **Digital Twin influence** | Home/digital twin signals if enabled |
| 11 | **Would another decision have been better?** | Counterfactual note in inspector |
| 12 | **Executive Brain vs LLM alignment** | Hero intent matches; LLM only narrates |

---

## Signal Fixtures

| Fixture ID | Signals | Expected intent bias |
|------------|---------|---------------------|
| BRAIN-FIX-001 | Low sleep (<5h) + 6 meetings | Recovery or low-cost task |
| BRAIN-FIX-002 | Post-workout HRV peak + empty calendar | Deep work / hero task |
| BRAIN-FIX-003 | Medication due window | Medication adherence intent |
| BRAIN-FIX-004 | Cycle luteal + female profile | Lower intensity; cycle-aware copy |
| BRAIN-FIX-005 | All tasks complete | Rest / capture / reflection |
| BRAIN-FIX-006 | Overdue high-priority task | Urgent hero elevation |
| BRAIN-FIX-007 | Active focus session | No hero swap mid-session |
| BRAIN-FIX-008 | Emergency mode active | Simplified intent set |

---

## Test Cases

### LO-BRAIN-FN-001 — Tick determinism

| Field | Value |
|-------|-------|
| Priority | P0 |
| Severity | S1 |
| Objective | Identical `BrainTickInput` → identical `decision.intent` |
| Steps | Call `ExecutiveBrainEngine.tick()` twice |
| Expected | Same intent; `generatedAt` may differ |
| Automated | `ExecutiveBrainEngineTests.swift` |
| Brain audit | Log signals from `world` snapshot |

### LO-BRAIN-FN-002 — Intent priority ordering

| Field | Value |
|-------|-------|
| Priority | P0 |
| Objective | Higher urgency tasks win hero eligibility |
| Automated | `IntentBuilderTests.swift`, `TaskHeroEligibilityTests.swift` |

### LO-BRAIN-FN-003 — Medication window reasoning

| Field | Value |
|-------|-------|
| Priority | P1 |
| Automated | `MedicationReasoningTests.swift` |

### LO-BRAIN-FN-004 — Decision history records issued intent

| Field | Value |
|-------|-------|
| Priority | P1 |
| Steps | Tick → query `DecisionHistoryStore` |
| Expected | Latest entry matches decision |
| UI | BrainInspectorView shows same trace |

### LO-BRAIN-FN-005 — World state builder aggregates all signal types

| Field | Value |
|-------|-------|
| Priority | P0 |
| Fixtures | BRAIN-FIX-001 through 008 |
| Expected | WorldState contains health, tasks, calendar, cycle (when eligible) |

### LO-BRAIN-FN-006 — Planning engine respects timeline items

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Plan slots align with fixed calendar blocks |

### LO-BRAIN-FN-007 — Explanation builder non-empty for every decision

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | User-facing explanation string length > 0 |

### LO-BRAIN-FN-010 — FlowDirector orchestrate publishes surface

| Field | Value |
|-------|-------|
| Priority | P0 |
| Steps | `orchestrate()` → check `surface.heroTask` |
| Automated | `FlowDirectorOrchestrationTests.swift` |

### LO-BRAIN-FN-011 — Task complete triggers re-orchestration

| Field | Value |
|-------|-------|
| Priority | P0 |
| Steps | `handleTaskCompleted` → surface updates |
| Data | Behavior memory append |
| Automated | `FlowDirectorOrchestrationTests.swift` |

### LO-BRAIN-FN-012 — Task defer records deferral

| Field | Value |
|-------|-------|
| Priority | P1 |
| Steps | `handleTaskDeferred` → behavior store |

### LO-BRAIN-FN-013 — Flow session end records duration

| Field | Value |
|-------|-------|
| Priority | P1 |
| Steps | `handleFlowSessionEnded` → behavior entry |

### LO-BRAIN-FN-014 — Confidence engine low confidence prompt

| Field | Value |
|-------|-------|
| Priority | P1 |
| Expected | Hero shows `lowConfidencePrompt` when appropriate |
| Automated | `FlowConfidenceEngineTests.swift` |

### LO-BRAIN-FN-015 — Scheduling engine no rule violations

| Field | Value |
|-------|-------|
| Priority | P0 |
| Automated | `FlowSchedulingRuleTests.swift`, `FlowSchedulingEngineTests.swift` |

---

## FlowDirector Integration

| Component | Role | Test |
|-----------|------|------|
| `EnvironmentContextProvider` | Fuse calendar, health, time, device | `EnvironmentContextProviderTests` |
| `BehaviorMemoryStore` | Append-only completion/defer/session | `BehaviorMemoryStoreTests` |
| `DefaultBehaviorAnalysisEngine` | Pattern detection | Manual + integration |
| `DeterministicFlowBriefingProvider` | Briefing lines without LLM | `FlowDirectorOrchestrationTests` |
| `FlowSchedulingEngine` | Slot selection | `FlowSchedulingEngineTests` |

### LO-BRAIN-INT-001 — App integration scenario

| Priority | P0 |
| Automated | `FlowDirectorAppIntegrationScenarioTests.swift` |
| Validates | End-to-end orchestrate with realistic session |

---

## ContextOrchestrator + BrainViewModel

| ID | Validation |
|----|------------|
| LO-BRAIN-UI-001 | `BrainViewModel.flowSurface` matches FlowDirector `surface` after orchestrate |
| LO-BRAIN-UI-002 | `ContextOrchestrator.briefing.hero.action.taskID` exists in `tasksVM.tasks` or nil with fallback copy |
| LO-BRAIN-UI-003 | BrainInspector trace matches last `BrainState`/decision history |
| LO-BRAIN-UI-004 | Hero button label from `HumanLanguage.outcomeHeadline` when task-based |

---

## Counterfactual Analysis Protocol

For manual brain audits on staging:

1. Capture `BrainTickInput` snapshot from Brain Inspector  
2. Note chosen intent and top 2 alternates from reasoning trace  
3. Ask: "If user had 8h sleep instead of 4h, would intent change?" — simulate with fixture  
4. Document in audit log if decision seems suboptimal → file improvement ticket (not necessarily blocker)  

---

## Executive Brain vs UI Timing

| Event | Max latency | Validation |
|-------|-------------|------------|
| Task complete → hero update | 2s | LO-IOS-FN-001 |
| Health sync complete → capacity refresh | 5s | FLOW-005 |
| App foreground → orchestrate | 3s | LO-BRAIN-FN-010 |
| Mode switch → same brain state | 0ms fork | FLOW-009 |

---

## Regression Mapping

| Unit test file | Brain components covered |
|----------------|-------------------------|
| `ExecutiveBrainEngineTests.swift` | Full tick pipeline |
| `IntentBuilderTests.swift` | Intent selection |
| `MedicationReasoningTests.swift` | Medication signals |
| `FlowDirectorOrchestrationTests.swift` | Orchestration |
| `FlowDirectorAppIntegrationScenarioTests.swift` | App scenario |
| `FlowSchedulingEngineTests.swift` | Scheduling |
| `FlowConfidenceEngineTests.swift` | Confidence |
| `FlowDirectorContractsTests.swift` | Protocol contracts |
| `ExecutiveRecommendationEngineTests.swift` | Core recommendations |
| `ContextEngineTests.swift` | Context fusion |
| `CompanionEngineTests.swift` | Continue session / story |

See [11-regression-suite.md](11-regression-suite.md) for full mapping.

---

## Moat validation cross-links

| Topic | Document |
|-------|----------|
| Was it the best decision? | [15-decision-quality-framework.md](15-decision-quality-framework.md) |
| Does the Brain learn? | [16-learning-validation.md](16-learning-validation.md) |
| Twin-specific recommendations | [17-digital-twin-validation.md](17-digital-twin-validation.md) |
| Executive Cost correctness | [19-executive-cost-validation.md](19-executive-cost-validation.md) |
| Wrong decisions log | [brain-bugs.md](brain-bugs.md) |
