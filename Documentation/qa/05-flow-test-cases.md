# 5. Flow Test Cases

**Document ID:** QA-05  
**Parent:** [README.md](README.md)

22 documented user flows with interruption, recovery, and offline variants.

---

## Flow Template

Each flow includes:

- **Preconditions** — Required system state  
- **Trigger** — User or system action starting flow  
- **Main Flow** — Happy path steps  
- **Alternative Flows** — Valid branches  
- **Interrupted Flow** — Phone call, background 30s, kill/relaunch  
- **Cancelled Flow** — User dismisses mid-way  
- **Background / Foreground** — Expected behaviour  
- **Offline Behaviour** — Airplane mode impact  
- **Error Behaviour** — API/permission failures  
- **Recovery** — Return to success state  
- **Success Criteria** — Objective pass conditions  

---

## P0 Flows

### FLOW-001 — Cold launch → Auth → Onboarding → Briefing

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Persona** | P1 New ADHD user |
| **Preconditions** | Fresh install OR factory reset; no auth token |
| **Trigger** | Tap app icon |
| **Main Flow** | 1. Launch → AuthView 2. Sign in Google/Apple 3. Onboarding overlay 4. Complete steps (skip health OK) 5. Land Briefing tab with seeded tasks |
| **Alternative** | Skip health on step health; skip cycle if not female |
| **Interrupted** | Kill app on onboarding step 5 → relaunch → resume same step |
| **Cancelled** | Dismiss auth → remain on AuthView |
| **Background** | Background during onboarding → state preserved |
| **Offline** | Auth requires network; show error if offline at sign-in |
| **Error** | Firebase auth fail → retry message |
| **Recovery** | Retry sign-in; onboarding error on organize → skip AI organize |
| **Success** | `UserLifeProfileStore.hasCompletedOnboarding == true`; Briefing visible; userName displayed |
| **Key files** | `ExperienceRootView`, `OnboardingView`, `FirebaseManager` |
| **Test IDs** | LO-IOS-FN-010, LO-DATA-FN-014 |

---

### FLOW-002 — Hero action → Start task → Complete → Brain refresh

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | Onboarding complete; ≥2 pending tasks; brain orchestrated |
| **Trigger** | Tap hero CTA on TodayView |
| **Main Flow** | 1. Note hero task ID 2. Tap Start 3. Mark complete 4. Within 2s hero updates to different task 5. Behavior memory recorded |
| **Alternative** | Defer instead of complete → new hero reflects deferral |
| **Interrupted** | Background after complete → foreground → hero still updated |
| **Offline** | Complete offline → sync queue; hero updates locally immediately |
| **Error** | Orchestrate fails → hero shows last known with retry toast |
| **Recovery** | Pull refresh / tab switch triggers `orchestrateBrain` |
| **Success** | Hero task ID ≠ completed ID; `BehaviorMemoryStore` has completion entry |
| **Key files** | `LookAfterMasterCanvas`, `AppShellState.orchestrateBrain`, `FlowDirector.handleTaskCompleted` |
| **Test IDs** | LO-IOS-FN-001, LO-AI-FN-002 |

---

### FLOW-003 — Voice capture → Inbox → Task creation

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | Mic + speech permissions granted; GLM key optional |
| **Trigger** | Open Inbox → voice capture |
| **Main Flow** | 1. Speak capture 2. Transcript appears 3. Process → category suggestion 4. Confirm → task created 5. Appears in TaskListView |
| **Alternative** | Text entry without voice |
| **Interrupted** | Phone call during recording → recording stops gracefully |
| **Cancelled** | Cancel capture → no inbox item |
| **Offline** | Queue inbox item; process when online if AI required |
| **Error** | Speech denied → show Settings link + text fallback |
| **Recovery** | Grant permission → retry |
| **Success** | Task in repository with correct userId; inbox item archived |
| **Key files** | `InboxView`, `VoiceCaptureView`, `TasksViewModel.createFromInbox` |
| **Test IDs** | LO-FEAT-FN-020, LO-AI-AI-002 |

---

### FLOW-004 — Executive planning conversation → Apply plan mutations

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | GLM key configured; ≥3 flexible tasks today |
| **Trigger** | Open ExecutivePlanningConversationView → "Reorganize my afternoon" |
| **Main Flow** | 1. Multi-turn conversation 2. GLM returns JSON mutations 3. Preview in ReschedulePreviewSheet 4. User confirms 5. Tasks rescheduled; timeline updates |
| **Alternative** | User revises plan in conversation before confirm |
| **Interrupted** | Network drop mid-GLM → partial response discarded; retry |
| **Cancelled** | Dismiss preview → no mutations applied |
| **Offline** | Show offline message; no partial apply |
| **Error** | Invalid JSON → parser error UI; deterministic fallback offer |
| **Recovery** | Retry prompt; manual edit in DailyPlanView |
| **Success** | No overlapping slots; life-commitments unchanged; parser success |
| **Key files** | `ExecutivePlanningViewModel`, `PlanningResponseParser`, `LLMPlanningEngine` |
| **Test IDs** | LO-AI-AI-001, LO-FEAT-FN-010 |

---

### FLOW-005 — HealthKit connect → Sync → Capacity update

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | Health enabled in settings; permissions not yet granted |
| **Trigger** | Connect Health in onboarding or settings |
| **Main Flow** | 1. System permission sheet 2. Grant 3. HealthSyncProgressView phases 4. Complete 5. ExecutiveCapacityCard shows band |
| **Alternative** | Skip health in onboarding → capacity uses defaults |
| **Interrupted** | Background during sync → resume on foreground |
| **Cancelled** | Deny permission → skip path with explanation |
| **Offline** | HealthKit local — sync does not need network |
| **Error** | HealthKit unavailable (simulator limits) → graceful message |
| **Recovery** | Settings → re-request authorization |
| **Success** | `healthSync.syncPhase == .complete`; capacity reflects sleep data |
| **Key files** | `HealthSyncService`, `HealthManager`, `HealthSyncProgressView` |
| **Test IDs** | LO-DATA-FN-010, LO-HEALTH-FN-001, FLOW-005 |

---

### FLOW-006 — Emergency mode → Reset → Return to briefing

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | User in overwhelm; ADHDFloatingDock or entry visible |
| **Trigger** | Enter Emergency Mode |
| **Main Flow** | 1. EmergencyModeView full screen 2. Bottom nav hidden 3. Optional PhysiologicalResetView 4. Exit emergency 5. Return to Briefing with nav restored |
| **Alternative** | Start focus from emergency |
| **Interrupted** | Kill app in emergency → relaunch → not stuck in emergency OR clear exit path |
| **Success** | `adhdVM.isEmergencyMode == false`; bottom nav visible |
| **Key files** | `ADHDViewModel`, `PhysiologicalResetView`, `LookAfterMasterCanvas.showsBottomNav` |
| **Test IDs** | LO-IOS-FN-040, LO-FEAT-FN-040 |

---

### FLOW-007 — Cycle log → Dashboard refresh → Briefing insight

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | Female gender; cycle tracking enabled; anchor set |
| **Trigger** | Log flow via CycleQuickLogSheet |
| **Main Flow** | 1. Open Cycle dashboard 2. Quick log 3. Save 4. Dashboard day/phase updates 5. Briefing shows cycle insight card if configured |
| **Alternative** | Import from HealthKit menstrual samples |
| **Error** | Mid-cycle flow must NOT reset anchor incorrectly |
| **Success** | `CycleEngine` day matches expected; insight phase-consistent |
| **Key files** | `CycleDashboardViewModel`, `CycleEngine`, `CycleLogRepository` |
| **Test IDs** | LO-CORE-FN-050, LO-CORE-FN-051, LO-FEAT-FN-030 |

---

### FLOW-008 — Factory reset → Re-onboard

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | Existing user with data |
| **Trigger** | Settings → Factory Reset → confirm |
| **Main Flow** | 1. Reset runs 2. All local stores cleared 3. Onboarding re-shown 4. Complete onboarding 5. Fresh task seed |
| **Interrupted** | Kill during reset → no corrupt partial state on relaunch |
| **Success** | No prior tasks; onboarding flag false until complete; Keychain GLM key cleared |
| **Key files** | `FactoryResetManager`, `SettingsView`, `ExperienceRootView` |
| **Test IDs** | LO-IOS-FN-060, LO-DATA-SEC-004 |

---

### FLOW-009 — Classic ↔ AI Executive mode switch (data parity)

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | Tasks, hero, health loaded in Classic |
| **Trigger** | Settings → switch to AI Executive |
| **Main Flow** | 1. Toggle mode 2. Animation 3. AIExecutiveCanvas shows same hero task count 4. Switch back 5. Data identical |
| **Interrupted** | Switch during brain orchestrate → no crash; eventual consistency |
| **Success** | Same task IDs, same hero intent, same userName |
| **Key files** | `ExperienceModeController`, `AppShellState` |
| **Test IDs** | LO-IOS-FN-020, LO-CORE-FN-014 |

---

### FLOW-010 — Widget / Live Activity focus session lifecycle

| Field | Detail |
|-------|--------|
| **Priority** | P0 |
| **Preconditions** | Physical device; Live Activities enabled |
| **Trigger** | Start focus session from FocusSessionView |
| **Main Flow** | 1. Start focus 2. Live Activity on Lock Screen / Dynamic Island 3. Timer counts 4. End session 5. LA dismisses; widget updates |
| **Alternative** | Pin Now to Lock Screen from settings |
| **Interrupted** | Kill app during focus → LA persists or clean end |
| **Success** | Widget shows current hero; LA matches timer |
| **Key files** | `LiveActivityManager`, `WidgetSyncService`, `FocusLiveActivity` |
| **Test IDs** | LO-WGT-FN-001, LO-WGT-FN-003 |

---

## P1 Flows

### FLOW-011 — Multi-day task planning confirm path

| Priority | P1 |
| Preconditions | GLM key; user requests "spread over 5 days" |
| Success | Preview shown before `createMultiDayTask`; no duplicate parents |
| Test IDs | LO-AI-AI-005, LO-FEAT-FN-005 |

### FLOW-012 — Decide-for-me pick among tasks

| Priority | P1 |
| Success | Pick from pending only; shame-free copy |
| Test IDs | LO-AI-AI-025 |

### FLOW-013 — Task import sheet bulk create

| Priority | P1 |
| Success | N tasks created from pasted list |

### FLOW-014 — Calendar sync add task events

| Priority | P1 |
| Preconditions | Calendar write permission |
| Success | EventKit events match scheduled tasks |

### FLOW-015 — AI Coach multi-turn thread

| Priority | P1 |
| Success | Tone matches settings; context from profile |

### FLOW-016 — macOS productivity session upload

| Priority | P1 |
| Success | Firebase receives session; iOS context refresh |

### FLOW-017 — Background analytics refresh

| Priority | P1 |
| Success | Cache updated; briefing cards reflect new patterns |

### FLOW-018 — Sign out → Sign in data restore

| Priority | P1 |
| Success | Cloud tasks restored; local wipe on sign out |

### FLOW-019 — Gender change disables cycle

| Priority | P1 |
| Steps | Settings → change gender to non-female |
| Success | Cycle module hidden; preferences disabled |

### FLOW-020 — GLM key configure unlocks AI features

| Priority | P1 |
| Success | Planning, coach, organize become available |

### FLOW-021 — End-of-day journal with speech

| Priority | P2 |
| Success | Journal entry saved; optional AI summary |

### FLOW-022 — Continue session after interruption

| Priority | P1 |
| Success | `ContinueSessionView` offers resume hero task |
| Key files | `ContinueSessionController` |

---

## Interrupted-Flow Standard (all P0)

Apply these variants to FLOW-001 through FLOW-010:

| Variant | Procedure | Pass criteria |
|---------|-----------|---------------|
| **INT-A** | Incoming phone call mid-flow | No crash; resumable or clean cancel |
| **INT-B** | Home → background 30s → foreground | State preserved or explicit recovery |
| **INT-C** | Force quit → relaunch | No corrupt data; re-entry path clear |
| **INT-D** | Revoke permission mid-flow (mic/health) | Graceful degradation message |
| **INT-E** | Network drop during GLM call | No partial mutation; retry offered |

---

## Flow Traceability Matrix

| Flow | Screens | Modules | Automated partial |
|------|---------|---------|-------------------|
| FLOW-001 | S26, S25, S05 | DATA, IOS | AuthenticationTests |
| FLOW-002 | S05, S14 | AI, FEAT, IOS | FlowDirectorOrchestrationTests |
| FLOW-003 | S27, S39 | AI, FEAT | — |
| FLOW-004 | S09, S18 | AI, FEAT | MultiDayTaskPlannerTests |
| FLOW-005 | S37, S08 | HEALTH, DATA | HealthSummaryRepositoryTests |
| FLOW-006 | S30, S33 | FEAT, IOS | — |
| FLOW-007 | S35, S36, S05 | CORE, FEAT | CycleEngineTests |
| FLOW-008 | S21, S25 | DATA, IOS | — |
| FLOW-009 | S02, S03, S21 | CORE, IOS | ExperienceModeTests |
| FLOW-010 | S31, S43–S45 | IOS, WGT | — |
