# 3. Module Test Cases

**Document ID:** QA-03  
**Parent:** [README.md](README.md)

Package-level validation for all six Swift packages plus app-layer integration points.

---

## LifeOSCore

**Path:** `Packages/LifeOSCore/`  
**Automated baseline:** 28 test files (Core + FlowScheduling)

### LO-CORE-FN-001 — Task recurrence engine weekly rule

| Field | Value |
|-------|-------|
| Priority | P0 |
| Severity | S2 |
| Feature | Task recurrence |
| Scenario | Weekly recurrence generates correct next occurrence |
| Objective | Verify `TaskRecurrenceEngine` advances dates without skip/double |
| Preconditions | Task with weekly rule, fixed calendar fixture |
| Steps | 1. Create recurring task 2. Mark complete 3. Inspect next due date |
| Expected | Next occurrence exactly +7 days; no duplicate instances |
| Performance | < 10ms per computation |
| Data | Local task store single instance per day |
| UI | N/A |
| A11y | N/A |
| AI | N/A |
| Regression | TaskListView, DailyPlanView |
| Automated | `TaskRecurrenceTests.swift` |

### LO-CORE-FN-050 — Cycle day calculation with manual anchor

| Field | Value |
|-------|-------|
| Priority | P0 |
| Severity | S1 |
| Feature | Cycle tracking |
| Scenario | Cycle day matches calendar from lastPeriodStart |
| Objective | Verify `CycleEngine` day index and countdown |
| Preconditions | Female profile, lastPeriodStart = 14 days ago, 28-day cycle |
| Steps | 1. Load cycle state 2. Compare day index 3. Verify countdown to next period |
| Expected | Day 15 (or equivalent phase); countdown ~13 days; no modulo wrap errors |
| Data | `CyclePreferencesStore`, `CycleLogStore` |
| Regression | CycleDashboardView, briefing cycle card |
| Automated | `CycleEngineTests.swift` |

### LO-CORE-FN-051 — New period detection from flow log gap

| Priority | P0 |
| Severity | S1 |
| Feature | Cycle tracking |
| Scenario | Flow log after 21+ day gap resets anchor |
| Objective | Verify `shouldTreatFlowAsNewPeriodStart()` guard |
| Preconditions | Existing anchor 25 days old, new flow log today |
| Steps | 1. Save flow log via repository 2. Recompute cycle state |
| Expected | Anchor moves to log date; day resets to 1 |
| Regression | CycleQuickLogSheet mid-cycle false reset |
| Automated | `CycleEngineTests.swift` |

### LO-CORE-FN-052 — Cycle insight builder phase grounding

| Priority | P1 |
| Severity | S2 |
| Feature | Cycle insights |
| Scenario | Insight text references correct phase only |
| Objective | `CycleInsightBuilder` output matches engine phase |
| Preconditions | Luteal phase fixture |
| Steps | Build insight → compare phase enum in output |
| Expected | No follicular language in luteal phase |
| AI | Insight must not diagnose medical conditions |
| Automated | `CycleInsightBuilderTests.swift` |

### LO-CORE-FN-010 — Hero eligibility excludes completed tasks

| Priority | P0 |
| Severity | S1 |
| Feature | Hero task selection |
| Objective | Completed tasks never selected as hero |
| Preconditions | 3 tasks, 1 completed today |
| Expected | Hero ID ≠ completed task ID |
| Automated | `TaskHeroEligibilityTests.swift` |

### LO-CORE-FN-011 — Day schedule reconciler no overlaps

| Priority | P0 |
| Severity | S2 |
| Feature | Scheduling |
| Objective | Reconciled schedule has no overlapping slots |
| Automated | `DayScheduleReconcilerTests.swift` |

### LO-CORE-FN-012 — Flow scheduling confidence bands

| Priority | P1 |
| Severity | S3 |
| Feature | Flow Director scheduling |
| Automated | `FlowConfidenceEngineTests.swift`, `FlowSchedulingEngineTests.swift` |

### LO-CORE-FN-013 — Onboarding task seeder creates routines

| Priority | P1 |
| Severity | S2 |
| Feature | Onboarding |
| Automated | `OnboardingTaskSeederTests.swift` |

### LO-CORE-FN-014 — Experience mode persistence

| Priority | P1 |
| Severity | S2 |
| Feature | Classic / AI Executive |
| Automated | `ExperienceModeTests.swift` |

### LO-CORE-FN-015 — Calm hero content sanitization

| Priority | P1 |
| Severity | S3 |
| Feature | Briefing copy |
| Automated | `CalmHeroContentTests.swift` |

---

## LifeOSData

**Path:** `Packages/LifeOSData/`  
**Automated baseline:** 12 test files

### LO-DATA-FN-001 — Task repository merge conflict resolution

| Priority | P0 |
| Severity | S1 |
| Feature | Cloud sync |
| Scenario | Local and remote task edits merge without data loss |
| Objective | Verify `TaskRepositoryMergeTests` scenarios |
| Preconditions | Same task edited offline on two logical clients |
| Steps | Sync both → inspect merged fields |
| Expected | Latest-wins or field-level merge per spec; no duplicate IDs |
| Data | Firestore document structure intact |
| Offline | Queue persists until reconnect |
| Automated | `TaskRepositoryMergeTests.swift` |

### LO-DATA-FN-010 — Health summary repository canonical userId

| Priority | P0 |
| Severity | S1 |
| Feature | Health sync |
| Scenario | Migration maps legacy userId to canonical |
| Objective | `HealthSummaryRepository.migrateAllSummariesToCanonicalUserId()` |
| Automated | `HealthSummaryRepositoryTests.swift` |

### LO-DATA-FN-011 — Health summary minimum sample threshold

| Priority | P0 |
| Severity | S1 |
| Feature | Executive capacity |
| Scenario | Partial HealthKit data does not produce false peak |
| Objective | Capacity band degrades gracefully with <3 sleep nights |
| Steps | Inject 1 night sleep → request capacity |
| Expected | Lower confidence or Recovery band; UI shows verification prompt |
| Regression | ExecutiveCapacityCard |
| Manual | LO-IOS-FN-045 |

### LO-DATA-FN-012 — Behavior memory append-only integrity

| Priority | P1 |
| Severity | S2 |
| Feature | Behavior memory |
| Automated | `BehaviorMemoryStoreTests.swift` |

### LO-DATA-FN-013 — Environment context provider fusion

| Priority | P1 |
| Severity | S2 |
| Feature | Flow Director signals |
| Automated | `EnvironmentContextProviderTests.swift` |

### LO-DATA-FN-014 — Firebase authentication state

| Priority | P0 |
| Severity | S1 |
| Feature | Auth |
| Automated | `AuthenticationTests.swift` |

### LO-DATA-FN-015 — Async timeout on hung network

| Priority | P1 |
| Severity | S2 |
| Feature | Reliability |
| Automated | `AsyncTimeoutTests.swift` |

### LO-DATA-FN-016 — Personal analytics engine cache

| Priority | P1 |
| Severity | S3 |
| Feature | Insights |
| Automated | `PersonalAnalyticsEngineTests.swift`, `AnalyticsCacheTests.swift` |

### LO-DATA-FN-017 — Full app integration simulated user

| Priority | P0 |
| Severity | S1 |
| Feature | Integration |
| Automated | `FullAppIntegrationTests.swift`, `SimulatedUserFlowTests.swift` |

### LO-DATA-FN-030 — Background analytics scheduler idempotent start

| Priority | P1 |
| Severity | S2 |
| Feature | Background services |
| Steps | Call `BackgroundAnalyticsScheduler.shared.start` twice |
| Expected | Single timer; no duplicate cache writes |
| Manual | LO-DATA-REL-030 |

### LO-DATA-SEC-001 — API keys not in UserDefaults

| Priority | P0 |
| Severity | S1 |
| Feature | Security |
| Steps | Inspect UserDefaults after GLM key save |
| Expected | Key only in Keychain via `KeychainStore` |
| Regression | APIKeysSettingsView |

---

## LifeOSAI

**Path:** `Packages/LifeOSAI/`

### LO-AI-AI-001 — Planning JSON schema compliance

| Priority | P0 |
| Severity | S1 |
| Feature | Executive planning |
| Scenario | GLM planning response parses without fallback |
| Objective | Valid JSON per `PlanningResponseParser` |
| Preconditions | Valid API key, ≥3 flexible tasks today |
| Steps | Open planning → request replan → apply mutations |
| Expected | No duplicate start times; life-commitments untouched |
| AI | Grounding: only existing tasks moved; no medical advice |
| Performance | Full apply < 15s WiFi |
| Regression | ExecutivePlanningConversationView |
| Manual | Required for release |

### LO-AI-AI-002 — Inbox processing valid category JSON

| Priority | P0 |
| Severity | S2 |
| Feature | Inbox |
| Objective | `inboxProcessingSystem` returns schema-valid JSON |
| AI | archive vs task decision grounded in capture text |

### LO-AI-AI-003 — Profile organize preserves facts

| Priority | P1 |
| Severity | S2 |
| Feature | Onboarding profile |
| Objective | No loss of commitments from markdown organize |
| AI | No contradiction with structured work hours |

### LO-AI-AI-004 — Executive capacity band enum only

| Priority | P1 |
| Severity | S2 |
| Feature | Capacity |
| Expected | One of: Peak Focus, Good, Moderate, Low, Recovery — no percentages |

### LO-AI-AI-005 — Multi-day planning confirm-before-create

| Priority | P0 |
| Severity | S1 |
| Feature | Multi-day tasks |
| Expected | No `createMultiDayTask` until user confirms preview |
| Automated | `MultiDayTaskPlannerTests.swift` (Features package) |

### LO-AI-FN-001 — FlowDirector orchestration publishes surface

| Priority | P0 |
| Severity | S1 |
| Feature | Flow Director |
| Automated | `FlowDirectorOrchestrationTests.swift` |

### LO-AI-FN-002 — FlowDirector task completion records behavior

| Priority | P0 |
| Severity | S2 |
| Feature | Behavior memory |
| Steps | `handleTaskCompleted` → verify behavior store entry |
| Automated | `FlowDirectorOrchestrationTests.swift` |

### LO-AI-FN-003 — GLM key manager rotation

| Priority | P1 |
| Severity | S2 |
| Feature | API keys |
| Automated | `GLMKeyManagerTests.swift` |

### LO-AI-FN-004 — Cognitive AI executive brain wrapper

| Priority | P1 |
| Severity | S2 |
| Automated | `CognitiveAITests.swift` |

### LO-AI-FN-005 — FlowDirector app integration scenario

| Priority | P0 |
| Severity | S1 |
| Automated | `FlowDirectorAppIntegrationScenarioTests.swift` |

---

## ExecutiveBrain

**Path:** `Packages/ExecutiveBrain/`

### LO-BRAIN-FN-001 — ExecutiveBrainEngine tick determinism

| Priority | P0 |
| Severity | S1 |
| Feature | Decision pipeline |
| Scenario | Same input → same intent |
| Objective | LLM not in pipeline; deterministic output |
| Preconditions | Fixed clock, fixed `BrainTickInput` fixture |
| Steps | Call `tick()` twice with identical input |
| Expected | Identical `decision.intent`; explanation references signals |
| Brain audit | Document signals, executive cost, simulation count |
| Automated | `ExecutiveBrainEngineTests.swift` |

### LO-BRAIN-FN-002 — Intent builder priority ordering

| Priority | P0 |
| Severity | S2 |
| Automated | `IntentBuilderTests.swift` |

### LO-BRAIN-FN-003 — Medication reasoning window

| Priority | P1 |
| Severity | S2 |
| Feature | Medication module |
| Automated | `MedicationReasoningTests.swift` |

### LO-BRAIN-FN-004 — Decision history store records issued intent

| Priority | P1 |
| Severity | S2 |
| Steps | Tick → verify `DecisionHistoryStore.recordIssued` |
| Regression | BrainInspectorView trace |

### LO-BRAIN-FN-005 — World state builder signal aggregation

| Priority | P0 |
| Severity | S2 |
| Fixtures | Low sleep + dense calendar, post-workout, cycle luteal |
| Manual | See [08-executive-brain-validation.md](08-executive-brain-validation.md) |

---

## LifeOSFeatures

**Path:** `Packages/LifeOSFeatures/`

### LO-FEAT-FN-001 — TasksViewModel create update delete

| Priority | P0 |
| Severity | S1 |
| Automated | `TasksViewModelInteractionTests.swift` |

### LO-FEAT-FN-002 — Task card UI contract hero eligibility

| Priority | P1 |
| Severity | S2 |
| Automated | `TaskCardUIContractTests.swift` |

### LO-FEAT-FN-003 — Daily briefing view model card order

| Priority | P1 |
| Severity | S2 |
| Automated | `DailyBriefingViewModelTests.swift` |

### LO-FEAT-FN-004 — Day assembler life model windows

| Priority | P0 |
| Severity | S2 |
| Automated | `DayAssemblerTests.swift` |

### LO-FEAT-FN-005 — Multi-day task detector

| Priority | P1 |
| Severity | S2 |
| Automated | `MultiDayTaskDetectorTests.swift` |

### LO-FEAT-FN-006 — Insights view model report generation

| Priority | P1 |
| Severity | S2 |
| Automated | `InsightsViewModelTests.swift` |

### LO-FEAT-FN-007 — Shopping list view model persistence

| Priority | P2 |
| Severity | S3 |
| Automated | `ShoppingListViewModelTests.swift` |

### LO-FEAT-FN-010 — Executive planning view model mutation apply

| Priority | P0 |
| Severity | S1 |
| Manual | FLOW-004 |

### LO-FEAT-FN-020 — Inbox view model task creation callback

| Priority | P0 |
| Severity | S2 |
| Manual | FLOW-003 |

### LO-FEAT-FN-030 — Cycle dashboard view model save log

| Priority | P0 |
| Severity | S1 |
| Manual | FLOW-007 |

### LO-FEAT-FN-040 — ADHD view model emergency mode state

| Priority | P0 |
| Severity | S2 |
| Manual | FLOW-006 |

---

## LifeOSHealth

**Path:** `Packages/LifeOSHealth/`

### LO-HEALTH-FN-001 — HealthManager authorization request

| Priority | P0 |
| Severity | S1 |
| Steps | Request authorization → verify read types |
| Expected | Sleep, HRV, heart rate, steps, menstrual (if enabled) |
| Manual | FLOW-005 |

### LO-HEALTH-FN-002 — Menstrual sample fetch date range

| Priority | P0 |
| Severity | S2 |
| Feature | Cycle HealthKit import |
| Automated | `LifeOSHealthTests.swift` |

### LO-HEALTH-FN-003 — HealthKit observer callback scheduling

| Priority | P1 |
| Severity | S2 |
| Manual | Background refresh after new sleep sample |

---

## iOS App Layer (cross-cutting)

### LO-IOS-FN-001 — Hero reflects latest brain tick

| Priority | P0 |
| Severity | S1 |
| Feature | Briefing hero |
| Objective | Hero CTA matches `ContextOrchestrator.briefing.hero` after task complete |
| Preconditions | Authenticated, onboarding done, ≥1 pending task |
| Steps | Complete hero task → observe hero within 2s |
| Expected | New hero; no stale task ID; why-now subtitle |
| Performance | Brain refresh < 2s warm |
| Data | `BehaviorMemoryStore.recordCompletion` |
| Regression | FlowDirector orchestrate race |

### LO-IOS-FN-020 — Experience mode data parity

| Priority | P0 |
| Severity | S1 |
| Manual | FLOW-009 |

### LO-IOS-FN-040 — Emergency mode hides bottom nav

| Priority | P0 |
| Severity | S2 |
| Steps | Enter emergency → verify `showsBottomNav == false` |

### LO-IOS-FN-060 — Factory reset wipes all local state

| Priority | P0 |
| Severity | S1 |
| Manual | FLOW-008 |

---

## macOS

### LO-MAC-FN-001 — Productivity tracker session upload

| Priority | P1 |
| Severity | S2 |
| Feature | Cross-device context |
| Preconditions | macOS signed in, Firebase connected |

### LO-MAC-FN-002 — Mac settings sync with iOS profile

| Priority | P2 |
| Severity | S3 |

---

## Widget

### LO-WGT-FN-001 — Now widget displays current hero task

| Priority | P0 |
| Severity | S2 |
| Manual | FLOW-010 |

### LO-WGT-FN-002 — Energy widget reflects capacity band

| Priority | P1 |
| Severity | S3 |

### LO-WGT-FN-003 — Live Activity focus session start/end

| Priority | P0 |
| Severity | S2 |
| Manual | FLOW-010 |

---

## Module Test Count Summary

| Package | P0 | P1 | P2 | Total |
|---------|----|----|----|----|
| LifeOSCore | 8 | 12 | 6 | 26 |
| LifeOSData | 10 | 8 | 4 | 22 |
| LifeOSAI | 8 | 10 | 4 | 22 |
| ExecutiveBrain | 6 | 6 | 2 | 14 |
| LifeOSFeatures | 10 | 12 | 8 | 30 |
| LifeOSHealth | 4 | 4 | 2 | 10 |
| iOS/MAC/WGT | 12 | 10 | 6 | 28 |
| **Total** | **58** | **62** | **32** | **152** |

*Additional cases in [04-screen-test-cases.md](04-screen-test-cases.md) bring total to ~180.*

---

## Security Module Tests (cross-cutting)

| ID | Area | Priority |
|----|------|----------|
| LO-DATA-SEC-001 | Keychain-only API keys | P0 |
| LO-DATA-SEC-002 | Firebase userId scoping on all writes | P0 |
| LO-DATA-SEC-003 | Health data excluded from analytics payloads | P0 |
| LO-DATA-SEC-004 | Factory reset clears Keychain GLM key | P0 |
| LO-DATA-SEC-005 | Speech audio not persisted to disk | P1 |
| LO-DATA-SEC-006 | GoogleService-Info.plist not in git | P0 |
| LO-DATA-SEC-007 | Sign-out clears sensitive in-memory caches | P1 |

See [06-edge-cases.md](06-edge-cases.md) for permission-denied variants.
