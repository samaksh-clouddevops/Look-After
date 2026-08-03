# 2. Test Matrix

**Document ID:** QA-02  
**Parent:** [README.md](README.md)

---

## Overview

**18 feature areas × 12 validation dimensions = 216 cells**

Legend:

| Symbol | Meaning |
|--------|---------|
| **A** | Automated (unit/integration test exists or planned) |
| **M** | Manual required |
| **R** | Required for release |
| **—** | Not applicable |

---

## Feature Areas

| # | Feature Area | Primary code paths |
|---|--------------|-------------------|
| F01 | Auth & Onboarding | `AuthView`, `OnboardingView`, `FirebaseManager` |
| F02 | Experience mode switch | `ExperienceModeController`, `ExperienceRootView` |
| F03 | Briefing / Today / Hero | `TodayView`, `ContextOrchestrator`, `BrainViewModel` |
| F04 | Executive Timeline | `ExecutiveLiveTimelineView`, `ExecutiveTimelineView` |
| F05 | Tasks | `TasksViewModel`, `TaskListView`, `TaskRecurrenceEngine` |
| F06 | Daily Plan / Planning | `ExecutivePlanningViewModel`, `PlanningResponseParser` |
| F07 | Universal Inbox | `InboxView`, `InboxViewModel` |
| F08 | ADHD scaffolding | `ADHDViewModel`, `ADHDViews`, `DecideForMeView` |
| F09 | AI Coach | `AICoachView`, `GLMService` |
| F10 | Executive Brain / Inspector | `ExecutiveBrainEngine`, `BrainInspectorView` |
| F11 | Health sync & capacity | `HealthSyncService`, `ExecutiveCapacityCard` |
| F12 | Cycle tracking | `CycleEngine`, `CycleDashboardView`, `CycleFeatureGate` |
| F13 | Life modules | `AllModulesGridView`, `LifeModulesViewModel` |
| F14 | Insights & Analytics | `InsightsViewModel`, `PersonalAnalyticsEngine` |
| F15 | Settings & Factory Reset | `SettingsView`, `FactoryResetManager` |
| F16 | Widget & Live Activity | `LifeOSWidgetBundle`, `LiveActivityManager` |
| F17 | macOS productivity | `MacContentView`, `ProductivityTracker` |
| F18 | Background services | `BackgroundAnalyticsScheduler`, health observers |
| F19 | Decision quality (DQS) | [15-decision-quality-framework.md](15-decision-quality-framework.md) |
| F20 | Learning adaptation | `BehaviorMemoryStore`, [16-learning-validation.md](16-learning-validation.md) |
| F21 | Digital twin | Profile + `DigitalTwinTabView`, [17-digital-twin-validation.md](17-digital-twin-validation.md) |
| F22 | Hallucination audit | GLM surfaces, [18-ai-hallucination-audit.md](18-ai-hallucination-audit.md) |
| F23 | Executive Cost | `ExecutiveCost`, `SimulationEngine`, [19-executive-cost-validation.md](19-executive-cost-validation.md) |

---

## Dimensions

| # | Dimension | Validation focus |
|---|-----------|------------------|
| D01 | Functional | Correct behaviour per spec |
| D02 | Visual | Layout, typography, design system |
| D03 | UX (3-second test) | Where/What/Why/On-tap clarity |
| D04 | Accessibility | VoiceOver, Dynamic Type, Reduce Motion |
| D05 | Performance | Latency, fps, memory, battery |
| D06 | Reliability | Crashes, hangs, race conditions |
| D07 | Data Integrity | Local + cloud consistency |
| D08 | AI Intelligence | GLM grounding, schema, safety |
| D09 | Offline | Airplane mode behaviour |
| D10 | Recovery | Error → retry → success |
| D11 | Security | Keys, auth, privacy |
| D12 | Regression | Covered by automated suite |
| D13 | Decision quality | DQS post-outcome — [15-decision-quality-framework.md](15-decision-quality-framework.md) |
| D14 | Human eval (HRS) | [20-human-evaluation-protocol.md](20-human-evaluation-protocol.md) |

---

## Matrix: F01–F09

| Feature | D01 Func | D02 Visual | D03 UX | D04 A11y | D05 Perf | D06 Rel | D07 Data | D08 AI | D09 Off | D10 Rec | D11 Sec | D12 Reg |
|---------|----------|------------|--------|----------|----------|---------|----------|--------|---------|---------|---------|---------|
| **F01 Auth & Onboarding** | R/A | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | R/M | R/A |
| **F02 Mode switch** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | — | R/M | R/M | — | R/A |
| **F03 Briefing/Hero** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | — | R/A |
| **F04 Timeline** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | — | R/M | R/M | — | R/M |
| **F05 Tasks** | R/A | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | — | R/A |
| **F06 Planning** | R/M | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | — | R/A |
| **F07 Inbox** | R/M | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | — | R/M |
| **F08 ADHD** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | — | R/M |
| **F09 AI Coach** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M | R/M |

---

## Matrix: F10–F18

| Feature | D01 Func | D02 Visual | D03 UX | D04 A11y | D05 Perf | D06 Rel | D07 Data | D08 AI | D09 Off | D10 Rec | D11 Sec | D12 Reg |
|---------|----------|------------|--------|----------|----------|---------|----------|--------|---------|---------|---------|---------|
| **F10 Brain/Inspector** | R/A | R/M | R/M | R/M | R/M | R/M | R/M | — | R/M | R/M | — | R/A |
| **F11 Health** | R/M | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | R/M | R/A |
| **F12 Cycle** | R/A | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | R/M | R/A |
| **F13 Life modules** | R/M | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | — | R/M |
| **F14 Insights** | R/A | R/M | R/M | R/M | R/M | R/M | R/A | R/M | R/M | R/M | — | R/A |
| **F15 Settings/Reset** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | — | R/M | R/M | R/M | R/M |
| **F16 Widget/LA** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | — | R/M | R/M | — | R/M |
| **F17 macOS** | R/M | R/M | R/M | R/M | R/M | R/M | R/M | — | R/M | R/M | R/M | R/M |
| **F18 Background** | R/M | — | — | — | R/M | R/M | R/A | — | R/M | R/M | R/M | R/A |

---

## Coverage Summary

| Dimension | Automated cells | Manual cells | N/A cells |
|-----------|-----------------|--------------|-----------|
| D01 Functional | 42 | 144 | 30 |
| D02 Visual | 0 | 162 | 54 |
| D03 UX | 0 | 162 | 54 |
| D04 Accessibility | 0 | 162 | 54 |
| D05 Performance | 0 | 162 | 54 |
| D06 Reliability | 18 | 144 | 54 |
| D07 Data Integrity | 36 | 126 | 54 |
| D08 AI Intelligence | 6 | 96 | 114 |
| D09 Offline | 0 | 162 | 54 |
| D10 Recovery | 0 | 162 | 54 |
| D11 Security | 6 | 66 | 144 |
| D12 Regression | 54 | 108 | 54 |

**Release minimum:** All **R** cells must have at least one linked test case (automated or manual ID).

---

## Feature → Test Case Mapping (P0 samples)

| Feature | Primary test IDs |
|---------|------------------|
| F01 | LO-IOS-FN-010–019, FLOW-001 |
| F02 | LO-IOS-FN-020, FLOW-009 |
| F03 | LO-IOS-FN-001–009, FLOW-002 |
| F04 | LO-IOS-FN-030–034 |
| F05 | LO-FEAT-FN-001–015, FLOW-003 |
| F06 | LO-AI-AI-001–010, FLOW-004 |
| F07 | LO-FEAT-FN-020–024 |
| F08 | LO-IOS-FN-040–049, FLOW-006 |
| F09 | LO-AI-AI-020–024 |
| F10 | LO-BRAIN-FN-001–015 |
| F11 | LO-DATA-FN-010–019, FLOW-005 |
| F12 | LO-CORE-FN-050–059, FLOW-007 |
| F13 | LO-FEAT-FN-030–045 |
| F14 | LO-FEAT-FN-050–054 |
| F15 | LO-IOS-FN-060–069, FLOW-008 |
| F16 | LO-WGT-FN-001–005, FLOW-010 |
| F17 | LO-MAC-FN-001–005 |
| F18 | LO-DATA-FN-030–035 |

See linked documents for full case definitions.

---

## Cross-Module Interaction Matrix (high-risk pairs)

| Module A | Module B | Risk | Test focus |
|----------|----------|------|------------|
| TasksVM | FlowDirector | Stale hero | LO-IOS-FN-001 |
| HealthSync | BriefingVM | Wrong capacity | LO-DATA-FN-012 |
| GLM | PlanningVM | Invalid JSON | LO-AI-AI-001 |
| Firebase | Onboarding | Auth race | FLOW-001 |
| CycleEngine | BriefingVM | Wrong phase insight | LO-CORE-FN-052 |
| FactoryReset | All stores | Incomplete wipe | FLOW-008 |
| ExperienceMode | AppShellState | Data fork | FLOW-009 |

---

## Execution Priority by Sprint

**Sprint 1 (P0):** F01, F03, F05, F06, F08, F10, F11, F15  
**Sprint 2 (P1):** F02, F04, F07, F09, F12, F13, F16  
**Sprint 3 (P2):** F14, F17, F18 + full edge matrix  
