# 11. Regression Suite

**Document ID:** QA-11  
**Parent:** [README.md](README.md)

Tiered regression strategy mapped to **54 existing unit test files**.

---

## Regression Tiers

| Tier | Trigger | Duration | Scope |
|------|---------|----------|-------|
| **T1** | Every commit / PR | ~5 min | Package `swift test` |
| **T2** | Pre-merge to main | ~15 min | T1 + `xcodebuild -scheme LookAfter-iOS test` |
| **T3** | Pre-release | ~45 min | T2 + manual P0 flows FLOW-001–010 |
| **T4** | Major release | ~3 days | All documented cases (~180) |

---

## Tier 1 — Package Unit Tests

Run from repo root:

```bash
cd Packages/LookAfterCore && swift test
cd Packages/ExecutiveBrain && swift test
cd Packages/LookAfterData && swift test
cd Packages/LookAfterFeatures && swift test
cd Packages/LookAfterAI && swift test
cd Packages/LookAfterHealth && swift test
```

### LookAfterCore (31 files)

| Test file | Regression IDs | Feature area |
|-----------|----------------|----------------|
| `CycleEngineTests.swift` | LO-CORE-FN-050, LO-CORE-FN-051 | F12 Cycle |
| `CycleInsightBuilderTests.swift` | LO-CORE-FN-052 | F12 Cycle |
| `TaskRecurrenceTests.swift` | LO-CORE-FN-001 | F05 Tasks |
| `TaskHeroEligibilityTests.swift` | LO-CORE-FN-010 | F03 Hero |
| `DayScheduleReconcilerTests.swift` | LO-CORE-FN-011 | F04 Timeline |
| `DaySlotAllocatorTests.swift` | LO-CORE-FN-011 | F06 Planning |
| `OnboardingTaskSeederTests.swift` | LO-CORE-FN-013 | F01 Onboarding |
| `ExperienceModeTests.swift` | LO-CORE-FN-014, LO-IOS-FN-020 | F02 Mode |
| `CalmHeroContentTests.swift` | LO-CORE-FN-015 | F03 Briefing |
| `LifeTimelinePresenterTests.swift` | LO-IOS-FN-030 | F04 Timeline |
| `HeroObjectiveResolverTests.swift` | LO-BRAIN-FN-002 | F10 Brain |
| `ExecutiveRecommendationEngineTests.swift` | LO-BRAIN-FN-001 | F10 Brain |
| `ContextEngineTests.swift` | LO-BRAIN-FN-005 | F10 Brain |
| `CompanionEngineTests.swift` | FLOW-022 | F03 Briefing |
| `SemanticDecisionTests.swift` | LO-BRAIN-FN-002 | F10 Brain |
| `TaskSemanticProfileTests.swift` | LO-FEAT-FN-001 | F05 Tasks |
| `IdealSleepPlannerTests.swift` | LO-DATA-FN-011 | F11 Health |
| `PostWakeDetectorTests.swift` | LO-BRAIN-FN-005 | F11 Health |
| `LifeModelValidatorTests.swift` | LO-AI-AI-010 | F01 Profile |
| `LifeProfileNameExtractorTests.swift` | LO-IOS-FN-010 | F01 Onboarding |
| `CoreDomainTests.swift` | LO-CORE-* | Core domain |
| `LookAfterCoreTests.swift` | LO-CORE-* | Core smoke |
| `FlowDirectorContractsTests.swift` | LO-BRAIN-FN-010 | F10 Brain |
| `FlowSchedulingRuleTests.swift` | LO-BRAIN-FN-015 | F10 Brain |
| `FlowSchedulingEngineTests.swift` | LO-BRAIN-FN-015 | F10 Brain |
| `FlowConfidenceEngineTests.swift` | LO-BRAIN-FN-014 | F10 Brain |

### ExecutiveBrain (3 files)

| Test file | Regression IDs |
|-----------|----------------|
| `ExecutiveBrainEngineTests.swift` | LO-BRAIN-FN-001 |
| `IntentBuilderTests.swift` | LO-BRAIN-FN-002 |
| `MedicationReasoningTests.swift` | LO-BRAIN-FN-003 |

### LookAfterData (12 files)

| Test file | Regression IDs |
|-----------|----------------|
| `TaskRepositoryMergeTests.swift` | LO-DATA-FN-001 |
| `HealthSummaryRepositoryTests.swift` | LO-DATA-FN-010 |
| `AuthenticationTests.swift` | LO-DATA-FN-014, FLOW-001 |
| `AsyncTimeoutTests.swift` | LO-DATA-FN-015, EDGE-N04 |
| `AnalyticsCacheTests.swift` | LO-DATA-FN-016 |
| `PersonalAnalyticsEngineTests.swift` | LO-FEAT-FN-006 |
| `BehaviorMemoryStoreTests.swift` | LO-DATA-FN-012, LO-AI-FN-002 |
| `EnvironmentContextProviderTests.swift` | LO-BRAIN-FN-005 |
| `DataPersistenceTests.swift` | LO-DATA-FN-017 |
| `FullAppIntegrationTests.swift` | LO-DATA-FN-017, FLOW-* |
| `SimulatedUserFlowTests.swift` | FLOW-001, FLOW-002 |
| `HealthSummaryRepositoryTests.swift` | FLOW-005 |

### LookAfterFeatures (11 files)

| Test file | Regression IDs |
|-----------|----------------|
| `TasksViewModelInteractionTests.swift` | LO-FEAT-FN-001 |
| `TaskCardUIContractTests.swift` | LO-FEAT-FN-002 |
| `DailyBriefingViewModelTests.swift` | LO-FEAT-FN-003 |
| `DayAssemblerTests.swift` | LO-FEAT-FN-004 |
| `MultiDayTaskDetectorTests.swift` | LO-AI-AI-005 |
| `MultiDayTaskPlannerTests.swift` | LO-AI-AI-005, FLOW-011 |
| `InsightsViewModelTests.swift` | LO-FEAT-FN-006 |
| `ShoppingListViewModelTests.swift` | LO-FEAT-FN-007 |
| `LookAfterFeaturesTests.swift` | LO-FEAT-* smoke |

### LookAfterAI (5 files)

| Test file | Regression IDs |
|-----------|----------------|
| `FlowDirectorOrchestrationTests.swift` | LO-AI-FN-001, LO-BRAIN-FN-010 |
| `FlowDirectorAppIntegrationScenarioTests.swift` | LO-BRAIN-INT-001 |
| `GLMKeyManagerTests.swift` | LO-AI-FN-003, LO-DATA-SEC-001 |
| `CognitiveAITests.swift` | LO-AI-FN-004 |

### LookAfterHealth (1 file)

| Test file | Regression IDs |
|-----------|----------------|
| `LookAfterHealthTests.swift` | LO-HEALTH-FN-002 |

---

## Tier 2 — Xcode iOS Test Scheme

```bash
xcodebuild -scheme LookAfter-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  test
```

Includes app-target tests if configured in scheme. Failures block merge.

---

## Tier 3 — P0 Manual Smoke (45 min)

Execute in order:

| # | Flow | Time est. |
|---|------|-----------|
| 1 | FLOW-001 Cold launch → onboarding | 8 min |
| 2 | FLOW-002 Hero complete refresh | 5 min |
| 3 | FLOW-003 Voice inbox | 5 min |
| 4 | FLOW-004 Planning apply | 8 min |
| 5 | FLOW-005 Health sync | 5 min |
| 6 | FLOW-006 Emergency mode | 3 min |
| 7 | FLOW-007 Cycle log | 4 min |
| 8 | FLOW-008 Factory reset | 5 min |
| 9 | FLOW-009 Mode switch | 2 min |
| 10 | FLOW-010 Widget/LA (device) | 5 min |

Plus interrupted variant **INT-C** (kill/relaunch) on FLOW-002.

---

## Tier 4 — Full Regression Buckets

| Bucket | Cases | Doc reference |
|--------|-------|---------------|
| Module P0/P1 | ~120 | [03-module-test-cases.md](03-module-test-cases.md) |
| Screen | ~30 | [04-screen-test-cases.md](04-screen-test-cases.md) |
| Flows P1 | 12 | [05-flow-test-cases.md](05-flow-test-cases.md) |
| Edge matrix | 50+ | [06-edge-cases.md](06-edge-cases.md) |
| AI golden set | 200 (target) | [07-ai-validation.md](07-ai-validation.md) |
| Brain fixtures | 8 | [08-executive-brain-validation.md](08-executive-brain-validation.md) |
| Performance | 12 | [09-performance-benchmarks.md](09-performance-benchmarks.md) |
| Accessibility | 15 | [10-accessibility-checklist.md](10-accessibility-checklist.md) |

---

## Coverage Gaps (manual-only until XCUITest added)

| Area | Current | Target |
|------|---------|--------|
| UI navigation | Manual | XCUITest P0 flows |
| Visual regression | Manual | Snapshot tests |
| GLM output | Manual rubric | CI eval job |
| Widget/LA | Manual device | WidgetKit test extensions |
| macOS | Manual | macOS UI tests |

---

## Regression Add Protocol

When fixing a defect:

1. Link defect to Test ID  
2. Add or extend unit test if logic-level  
3. Add manual case if UI-only  
4. Update this mapping table  
5. Verify Tier appropriate (S1 → add to T1 or T2 if possible)  

---

## Smoke Test Pass Log

| Date | Build | T1 | T2 | T3 | Sign-off |
|------|-------|----|----|-----|----------|
| | | ☐ | ☐ | ☐ | |
