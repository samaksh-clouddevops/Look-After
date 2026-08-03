# 4. Screen Test Cases

**Document ID:** QA-04  
**Parent:** [README.md](README.md)

All iOS, macOS, and Widget surfaces with **15-field screen specs** plus linked test case IDs.

---

## Screen Index (47 surfaces)

| # | Screen | File |
|---|--------|------|
| S01 | ExperienceRootView | `Apps/LookAfter-iOS/Experience/ExperienceRootView.swift` |
| S02 | LookAfterMasterCanvas | `Apps/LookAfter-iOS/Views/LookAfterMasterCanvas.swift` |
| S03 | AIExecutiveCanvas | `Apps/LookAfter-iOS/Experience/AIExecutive/AIExecutiveCanvas.swift` |
| S04 | LookAfterBottomNav | `Apps/LookAfter-iOS/Views/Navigation/LookAfterBottomNav.swift` |
| S05 | TodayView | `Apps/LookAfter-iOS/Views/Briefing/TodayView.swift` |
| S06 | DailyBriefingView | `Apps/LookAfter-iOS/Views/Briefing/DailyBriefingView.swift` |
| S07 | DailyBriefingCustomizationView | `Apps/LookAfter-iOS/Views/Briefing/DailyBriefingCustomizationView.swift` |
| S08 | ExecutiveCapacityCard | `Apps/LookAfter-iOS/Views/Briefing/ExecutiveCapacityCard.swift` |
| S09 | ExecutivePlanningConversationView | `Apps/LookAfter-iOS/Views/Briefing/ExecutivePlanningConversationView.swift` |
| S10 | ExecutiveLiveTimelineView | `Apps/LookAfter-iOS/Views/Briefing/ExecutiveLiveTimelineView.swift` |
| S11 | ExecutiveAssistantSheet | `Apps/LookAfter-iOS/Views/Briefing/ExecutiveAssistantSheet.swift` |
| S12 | ExecutiveTodayView | `Apps/LookAfter-iOS/Experience/AIExecutive/ExecutiveTodayView.swift` |
| S13 | ExecutiveTimelineView | `Apps/LookAfter-iOS/Experience/AIExecutive/ExecutiveTimelineView.swift` |
| S14 | TaskListView | `Apps/LookAfter-iOS/Views/Tasks/TaskListView.swift` |
| S15 | DailyPlanView | `Apps/LookAfter-iOS/Views/Tasks/DailyPlanView.swift` |
| S16 | TaskCardStackView | `Apps/LookAfter-iOS/Views/Tasks/TaskCardStackView.swift` |
| S17 | TaskImportSheet | `Apps/LookAfter-iOS/Views/Tasks/TaskImportSheet.swift` |
| S18 | ReschedulePreviewSheet | `Apps/LookAfter-iOS/Views/Tasks/ReschedulePreviewSheet.swift` |
| S19 | BrainDashboardView | `Apps/LookAfter-iOS/Views/Brain/BrainDashboardView.swift` |
| S20 | BrainInspectorView | `Apps/LookAfter-iOS/Experience/AIExecutive/BrainInspectorView.swift` |
| S21 | SettingsView | `Apps/LookAfter-iOS/Views/Settings/SettingsView.swift` |
| S22 | APIKeysSettingsView | `Apps/LookAfter-iOS/Views/Settings/APIKeysSettingsView.swift` |
| S23 | GLMConfigurationSettingsView | `Apps/LookAfter-iOS/Views/Settings/GLMConfigurationSettingsView.swift` |
| S24 | InsightsDashboardView | `Apps/LookAfter-iOS/Views/Insights/InsightsDashboardView.swift` |
| S25 | OnboardingView | `Apps/LookAfter-iOS/Views/Onboarding/OnboardingView.swift` |
| S26 | AuthView | `Apps/LookAfter-iOS/Views/Auth/AuthView.swift` |
| S27 | InboxView | `Apps/LookAfter-iOS/Views/Inbox/InboxView.swift` |
| S28 | AICoachView | `Apps/LookAfter-iOS/Views/Coach/AICoachView.swift` |
| S29 | AllModulesGridView | `Apps/LookAfter-iOS/Views/Modules/AllModulesGridView.swift` |
| S30 | EmergencyModeView | `Apps/LookAfter-iOS/Views/ADHD/ADHDViews.swift` |
| S31 | FocusSessionView | `Apps/LookAfter-iOS/Views/ADHD/ADHDViews.swift` |
| S32 | DecideForMeView | `Apps/LookAfter-iOS/Views/ADHD/DecideForMeView.swift` |
| S33 | PhysiologicalResetView | `Apps/LookAfter-iOS/Views/ADHD/PhysiologicalResetView.swift` |
| S34 | ADHDFloatingDockView | `Apps/LookAfter-iOS/Views/Shared/ADHDFloatingDockView.swift` |
| S35 | CycleDashboardView | `Apps/LookAfter-iOS/Views/Health/CycleDashboardView.swift` |
| S36 | CycleQuickLogSheet | `Apps/LookAfter-iOS/Views/Health/CycleQuickLogSheet.swift` |
| S37 | HealthSyncProgressView | `Apps/LookAfter-iOS/Views/Shared/HealthSyncProgressView.swift` |
| S38 | HealthDetailView | `Apps/LookAfter-iOS/Experience/AIExecutive/HealthDetailView.swift` |
| S39 | VoiceCaptureView | `Apps/LookAfter-iOS/Views/Shared/VoiceCaptureView.swift` |
| S40 | ContinueSessionView | `Apps/LookAfter-iOS/Experience/AIExecutive/ContinueSessionView.swift` |
| S41 | TodaysStoryView | `Apps/LookAfter-iOS/Experience/AIExecutive/TodaysStoryView.swift` |
| S42 | ExecutiveProfileView | `Apps/LookAfter-iOS/Experience/AIExecutive/ExecutiveProfileView.swift` |
| S43 | NowWidgetView | `Apps/LookAfterWidget/LookAfterWidgetBundle.swift` |
| S44 | EnergyWidgetView | `Apps/LookAfterWidget/LookAfterWidgetBundle.swift` |
| S45 | FocusLiveActivity | `Apps/LookAfterWidget/FocusLiveActivity.swift` |
| S46 | MacContentView | `Apps/LookAfter-macOS/Views/MacContentView.swift` |
| S47 | MacSettingsView | `Apps/LookAfter-macOS/Views/MacSettingsView.swift` |

**Package-hosted module screens** (entered via S29): CalendarIntelligenceView, MedicationView, HomeManagementView, TravelPlannerView, CreativityWorkspaceView, LearningKnowledgeView, AIMemoryView, FinanceBillsView, HydrationNutritionView, ShoppingInventoryView, RelationshipsView, ReflectionJournalView — each inherits module spec template below.

---

## Root & Navigation

### S01 — ExperienceRootView

| Field | Specification |
|-------|---------------|
| **Purpose** | Root switcher between Classic and AI Executive; hosts onboarding overlay |
| **User Goal** | Land in correct experience with data already loading |
| **Dependencies** | `FirebaseManager`, `HealthSyncService`, `AppShellState`, `ExperienceModeController` |
| **Entry Points** | App cold/warm launch |
| **Exit Points** | N/A (persistent root) |
| **Brain Behaviour** | Triggers `shell.bootstrap` on auth; `refreshContext` on health complete |
| **AI Behaviour** | None directly |
| **UI Behaviour** | Mode switch animation; onboarding full-screen overlay when `!hasCompletedOnboarding` |
| **Animations** | Spring 0.45s mode transition; 0.25s onboarding fade |
| **Data Sources** | Firebase auth, UserLifeProfileStore, HealthKit observers |
| **Performance** | Interactive shell < 2.5s cold launch |
| **A11y** | VoiceOver announces experience mode on change |
| **Failure States** | Unauthenticated → auth gate; health observer fail → silent retry |
| **Recovery** | `factoryResetGeneration` re-shows onboarding |
| **Analytics** | Bootstrap timing, health sync phase transitions |
| **Regression Risks** | Double bootstrap; onboarding + mode race |

**Test cases:** LO-IOS-FN-070, FLOW-001, FLOW-009

---

### S02 — LookAfterMasterCanvas

| Field | Specification |
|-------|---------------|
| **Purpose** | Classic mode main shell — tabs, hero, sheets |
| **User Goal** | See what to do now and navigate life domains |
| **Dependencies** | All `AppShellState` VMs, 15+ sheet `@State` flags |
| **Entry Points** | Classic mode default tab Briefing |
| **Exit Points** | Settings, module sheets, emergency mode |
| **Brain Behaviour** | Hero from `contextOrchestrator.briefing?.hero` or `brainVM.flowSurface` |
| **AI Behaviour** | Decide-for-me, planning speech, GLM when key configured |
| **UI Behaviour** | Tab content swap; bottom nav unless emergency/focus |
| **Animations** | Tab ease 0.2s; sheet presentations |
| **Data Sources** | Tasks, health, calendar, behavior memory |
| **Performance** | Tab switch 60fps; hero refresh < 2s |
| **A11y** | Bottom nav selected trait; hero button ≥44pt |
| **Failure States** | No tasks → empty hero copy; GLM unavailable → deterministic fallback |
| **Recovery** | Pull refresh context; toast on errors |
| **Analytics** | Hero tap, tab switches, sheet opens |
| **Regression Risks** | Stale hero; sheet state leak; `showsBottomNav` |

**Test cases:** LO-IOS-FN-001, LO-IOS-FN-040, FLOW-002

---

### S03 — AIExecutiveCanvas

| Field | Specification |
|-------|---------------|
| **Purpose** | AI Executive mode — timeline-first, minimal chrome |
| **User Goal** | Trust proactive orchestration surface |
| **Dependencies** | Same `AppShellState` as S02 |
| **Entry Points** | Settings experience toggle |
| **Exit Points** | Switch back to Classic |
| **Brain Behaviour** | Full FlowDirector surface on `brainVM.flowSurface` |
| **AI Behaviour** | Capture sheet, today's story narrative |
| **UI Behaviour** | Canvas layout vs tab bar |
| **Animations** | Mode switch from ExperienceRootView |
| **Data Sources** | Identical to Classic |
| **Performance** | Parity with S02 load times |
| **A11y** | Timeline items readable in order |
| **Failure States** | Empty timeline → guided empty state |
| **Recovery** | Manual capture → inbox |
| **Regression Risks** | Data desync vs Classic (FLOW-009) |

**Test cases:** FLOW-009, LO-IOS-FN-020

---

### S04 — LookAfterBottomNav

| Field | Specification |
|-------|---------------|
| **Purpose** | Five-tab primary navigation |
| **User Goal** | Jump between Briefing, Timeline, Work, Brain, You |
| **Tabs** | briefing, timeline, work, brain, you |
| **Brain Behaviour** | None |
| **AI Behaviour** | None |
| **UI Behaviour** | Selected icon fill; haptic on tap |
| **Animations** | 0.2s ease selection |
| **A11y** | `.accessibilityLabel`, `.isSelected` trait |
| **Failure States** | Hidden during emergency/focus |
| **Regression Risks** | Tab state reset on mode switch |

**Test cases:** LO-IOS-A11Y-004, LO-IOS-FN-041

---

## Briefing / Today Tab

### S05 — TodayView

| Field | Specification |
|-------|---------------|
| **Purpose** | Primary "now" surface — hero, metrics, journal |
| **User Goal** | Answer in 3s: what should I do next and why |
| **Dependencies** | `DailyBriefingViewModel`, `BrainViewModel`, `ContextOrchestrator` |
| **Entry Points** | Briefing tab default |
| **Exit Points** | Hero tap → task/focus; sheets for planning |
| **Brain Behaviour** | Hero CTA binds to top intent; capacity from health |
| **AI Behaviour** | End-of-day journal may use speech → GLM |
| **UI Behaviour** | Scroll stack: hero, capacity, timeline strip, cards |
| **Performance** | First paint < 500ms after shell ready |
| **A11y** | Hero VoiceOver: title + why + button hint |
| **Failure States** | No health → capacity card explains opt-in |
| **Recovery** | Settings link for health enable |
| **Regression Risks** | LO-IOS-FN-001 stale hero |

**Test cases:** LO-IOS-FN-001, LO-IOS-UX-005, LO-IOS-A11Y-005

---

### S06 — DailyBriefingView

| Field | Specification |
|-------|---------------|
| **Purpose** | Card stack briefing (weather, gaps, story) |
| **User Goal** | Scan contextual day overview |
| **Brain Behaviour** | Cards fed by `DailyBriefingViewModel` |
| **AI Behaviour** | Life gaps may reference LLM insights |
| **Data Sources** | Analytics cache, weather stub, tasks |
| **Regression Risks** | Card order after customization |

**Test cases:** LO-FEAT-FN-003, LO-IOS-FN-005

---

### S07 — DailyBriefingCustomizationView

| Field | Specification |
|-------|---------------|
| **Purpose** | Reorder/hide briefing cards |
| **User Goal** | Personalize briefing density |
| **Data Sources** | UserDefaults / profile persistence |
| **Recovery** | Reset to defaults |

**Test cases:** LO-IOS-FN-006

---

### S08 — ExecutiveCapacityCard

| Field | Specification |
|-------|---------------|
| **Purpose** | Show executive capacity band from health |
| **User Goal** | Understand energy for planning decisions |
| **Brain Behaviour** | Band influences scheduling confidence |
| **AI Behaviour** | Optional LLM reason text via `executiveCapacitySystem` |
| **Failure States** | Insufficient sleep data → Recovery + verification link |
| **Regression Risks** | LO-DATA-FN-011 partial data |

**Test cases:** LO-DATA-FN-011, LO-IOS-FN-045

---

### S09 — ExecutivePlanningConversationView

| Field | Specification |
|-------|---------------|
| **Purpose** | Multi-turn voice/text planning with GLM |
| **User Goal** | Reorganize day through conversation |
| **Dependencies** | `ExecutivePlanningViewModel`, `SpeechRecognitionManager` |
| **AI Behaviour** | JSON mutations via `PlanningResponseParser` |
| **Performance** | First response < 3s; apply < 15s |
| **Failure States** | Parse error → user-visible retry; offline → queue message |
| **Security** | Speech not logged |

**Test cases:** LO-AI-AI-001, FLOW-004

---

### S10 — ExecutiveLiveTimelineView

| Field | Specification |
|-------|---------------|
| **Purpose** | Live day timeline with calendar reconciliation |
| **User Goal** | See day shape and conflicts |
| **Brain Behaviour** | Slots from `DayAssembler` + calendar |
| **Failure States** | Calendar denied → tasks-only timeline |

**Test cases:** LO-IOS-FN-030, LO-FEAT-FN-004

---

### S11 — ExecutiveAssistantSheet

| Field | Specification |
|-------|---------------|
| **Purpose** | Quick voice capture assistant |
| **User Goal** | Capture without leaving briefing |
| **Permissions** | Microphone, Speech Recognition |
| **Recovery** | Permission denied → text fallback |

**Test cases:** LO-IOS-FN-035, FLOW-003

---

## Work / Tasks

### S14 — TaskListView

| Field | Specification |
|-------|---------------|
| **Purpose** | Full task CRUD and filtering |
| **User Goal** | Manage all tasks across life areas |
| **Dependencies** | `TasksViewModel`, `TaskDecomposer` |
| **Brain Behaviour** | Task complete triggers FlowDirector |
| **AI Behaviour** | Decompose/import use GLM when keyed |
| **Performance** | 500 tasks scroll 60fps |
| **A11y** | Row actions ≥44pt; swipe actions labeled |
| **Offline** | Local queue; sync on reconnect |
| **Regression Risks** | Merge conflicts |

**Test cases:** LO-FEAT-FN-001, LO-DATA-FN-001, LO-IOS-PERF-014

---

### S15 — DailyPlanView

| Field | Specification |
|-------|---------------|
| **Purpose** | Today's scheduled task timeline |
| **User Goal** | Execute plan in time order |
| **Brain Behaviour** | Reconcile with life model windows |

**Test cases:** LO-FEAT-FN-004, LO-CORE-FN-011

---

### S16 — TaskCardStackView

| Field | Specification |
|-------|---------------|
| **Purpose** | Swipeable task cards for focus picking |
| **User Goal** | Low-friction task initiation (ADHD) |
| **UI Behaviour** | Card stack physics; complete/defer gestures |

**Test cases:** LO-FEAT-FN-002, LO-IOS-UX-016

---

### S17 — TaskImportSheet

| Field | Specification |
|-------|---------------|
| **Purpose** | Bulk import tasks from text |
| **AI Behaviour** | GLM parses list → task drafts |

**Test cases:** FLOW-011 (P1)

---

### S18 — ReschedulePreviewSheet

| Field | Specification |
|-------|---------------|
| **Purpose** | Preview AI/day replan before apply |
| **User Goal** | Trust but verify schedule changes |

**Test cases:** LO-AI-AI-001

---

## Brain Tab

### S19 — BrainDashboardView

| Field | Specification |
|-------|---------------|
| **Purpose** | Brain status, recommendations, top tasks |
| **User Goal** | Understand system reasoning at glance |
| **Brain Behaviour** | Displays `BrainViewModel` state |
| **Regression Risks** | Mismatch vs BrainInspector trace |

**Test cases:** LO-BRAIN-FN-001, LO-IOS-FN-019

---

### S20 — BrainInspectorView

| Field | Specification |
|-------|---------------|
| **Purpose** | Debug/explain reasoning trace |
| **User Goal** | See why this recommendation (power users) |
| **Brain Behaviour** | Must match `ExecutiveBrainEngine` output |
| **Regression Risks** | Stale trace after tick |

**Test cases:** LO-BRAIN-FN-004, LO-BRAIN-UX-020

---

## Settings & Auth

### S21 — SettingsView

| Field | Specification |
|-------|---------------|
| **Purpose** | Account, profile, experience, health, ADHD, factory reset |
| **Sections** | Account, Profile/Gender, Experience, Health, Cycle (gated), ADHD, AI, Danger zone |
| **Security** | Sign out, factory reset |
| **Regression Risks** | Gender change → cycle disable; reset incomplete |

**Test cases:** LO-IOS-FN-060, FLOW-008, LO-CORE-FN-051

---

### S25 — OnboardingView

| Field | Specification |
|-------|---------------|
| **Purpose** | First-run 9-step setup |
| **Steps** | welcome → name → gender → schedule → commitments → profile → health → cycle (female) → ready |
| **Brain Behaviour** | Seeds tasks on complete via `refreshTasksFromProfile` |
| **AI Behaviour** | Profile organize requires GLM key |
| **Failure States** | Health skip; organize error message |
| **Regression Risks** | Cycle shown for non-female; re-show after reset |

**Test cases:** LO-IOS-FN-010–019, FLOW-001

---

### S26 — AuthView

| Field | Specification |
|-------|---------------|
| **Purpose** | Google/Apple sign-in |
| **Security** | Firebase auth tokens; no password storage |
| **Failure States** | Network error, cancelled sign-in |

**Test cases:** LO-DATA-FN-014, FLOW-001

---

## ADHD Surfaces

### S30 — EmergencyModeView

| Field | Specification |
|-------|---------------|
| **Purpose** | Overwhelm escape hatch — simplified UI |
| **User Goal** | Reduce cognitive load immediately |
| **UI Behaviour** | Hides bottom nav; large calming actions |
| **Recovery** | Exit → PhysiologicalReset or briefing |

**Test cases:** LO-IOS-FN-040, FLOW-006

---

### S31 — FocusSessionView

| Field | Specification |
|-------|---------------|
| **Purpose** | Timed focus with Live Activity |
| **User Goal** | Single-task attention scaffold |
| **Dependencies** | `LiveActivityManager`, `ADHDViewModel` |
| **Performance** | Timer drift < 1s per 25 min |
| **Reduce Motion** | Timer animation respects setting |

**Test cases:** LO-WGT-FN-003, FLOW-010

---

### S32 — DecideForMeView

| Field | Specification |
|-------|---------------|
| **Purpose** | AI picks among pending tasks |
| **AI Behaviour** | Options from actual task set only (`DecideForMePicker`) |
| **Safety** | No shame language |

**Test cases:** LO-AI-AI-025, FLOW-012 (P1)

---

### S33 — PhysiologicalResetView

| Field | Specification |
|-------|---------------|
| **Purpose** | Guided breathing / grounding |
| **User Goal** | Regulate before returning to tasks |
| **AI Behaviour** | None |

**Test cases:** LO-IOS-FN-048, FLOW-006

---

## Health & Cycle

### S35 — CycleDashboardView

| Field | Specification |
|-------|---------------|
| **Purpose** | Cycle phase, day, countdown, insights |
| **User Goal** | Understand cycle context for planning |
| **Dependencies** | `CycleDashboardViewModel`, `CycleEngine`, `CycleFeatureGate` |
| **Brain Behaviour** | Cycle signal in world state (female only) |
| **AI Behaviour** | Phase insight via `cycleInsightPrompt` |
| **Entry Points** | Modules grid (gated), Settings |
| **Failure States** | No anchor date → prompt setup |
| **Regression Risks** | Wrong day count (LO-CORE-FN-050) |

**Test cases:** LO-CORE-FN-050–052, FLOW-007

---

### S36 — CycleQuickLogSheet

| Field | Specification |
|-------|---------------|
| **Purpose** | Quick log flow/symptoms |
| **Data Sources** | `CycleLogRepository`, HealthKit menstrual samples |
| **Regression Risks** | Mid-cycle flow false period start |

**Test cases:** LO-CORE-FN-051, LO-FEAT-FN-030

---

### S37 — HealthSyncProgressView

| Field | Specification |
|-------|---------------|
| **Purpose** | Multi-phase health backfill UI |
| **Phases** | connect → syncing → complete / error |
| **Performance** | 90-day backfill < 60s |
| **Recovery** | Retry on error; skip path |

**Test cases:** FLOW-005, LO-DATA-FN-010

---

## Coach, Inbox, Modules

### S27 — InboxView

| Field | Specification |
|-------|---------------|
| **Purpose** | Universal capture inbox |
| **AI Behaviour** | Categorize via `inboxProcessingSystem` |
| **Offline** | Queue captures locally |

**Test cases:** FLOW-003, LO-AI-AI-002

---

### S28 — AICoachView

| Field | Specification |
|-------|---------------|
| **Purpose** | Conversational ADHD coach |
| **AI Behaviour** | `coachSystemPrompt`; tone from settings |
| **Safety** | No medical diagnosis; crisis redirect copy |

**Test cases:** LO-AI-AI-020, LO-IOS-SEC-028

---

### S29 — AllModulesGridView

| Field | Specification |
|-------|---------------|
| **Purpose** | Hub for 15 life domain modules |
| **User Goal** | Discover and enter any life area |
| **Gating** | Cycle tile only if `CycleFeatureGate.isEligible` |
| **Regression Risks** | Stale badge counts |

**Test cases:** LO-IOS-FN-029, LO-FEAT-FN-030–045

---

## Module Screen Template (S29 destinations)

Apply to: FinanceBillsView, HydrationNutritionView, ShoppingInventoryView, RelationshipsView, ReflectionJournalView, CalendarIntelligenceView, MedicationView, HomeManagementView, TravelPlannerView, CreativityWorkspaceView, LearningKnowledgeView, AIMemoryView.

| Field | Specification |
|-------|---------------|
| **Purpose** | Domain-specific CRUD and insights |
| **User Goal** | Manage one life area without cognitive overload |
| **Dependencies** | `LifeModulesViewModel`, Firebase repositories |
| **Brain Behaviour** | Module signals may feed world state (medication, home) |
| **AI Behaviour** | Semantic memory search (AIMemory); social check-in drafts |
| **UI Behaviour** | PremiumScreen + DesignSystem components |
| **Performance** | List load < 1s for <100 items |
| **A11y** | Section headers; form fields labeled |
| **Failure States** | Empty state via `EmptyStateView` |
| **Offline** | Local persistence then sync |
| **Recovery** | Pull to refresh |
| **Regression Risks** | Cross-module data (shopping → tasks) |

**Representative test IDs:** LO-FEAT-FN-031 (Finance), LO-FEAT-FN-032 (Shopping), LO-FEAT-FN-007, LO-FEAT-FN-033 (Calendar), LO-BRAIN-FN-003 (Medication)

---

## Widget & macOS

### S43 — NowWidgetView / S44 — EnergyWidgetView

| Field | Specification |
|-------|---------------|
| **Purpose** | Home Screen glanceable hero and energy |
| **Data Sources** | `WidgetDataStore` via `WidgetSyncService` |
| **Performance** | Timeline refresh within 15 min of app update |
| **Failure States** | Placeholder when no data |

**Test cases:** LO-WGT-FN-001, LO-WGT-FN-002, FLOW-010

---

### S45 — FocusLiveActivity

| Field | Specification |
|-------|---------------|
| **Purpose** | Dynamic Island / Lock Screen focus timer |
| **Dependencies** | `LiveActivityManager`, `FlowActivityAttributes` |
| **Recovery** | End session from app if LA stale |

**Test cases:** LO-WGT-FN-003

---

### S46 — MacContentView / S47 — MacSettingsView

| Field | Specification |
|-------|---------------|
| **Purpose** | macOS productivity context upload |
| **User Goal** | Passive desktop context for iOS brain |
| **Dependencies** | `ProductivityTracker`, Firebase |
| **Security** | Same auth as iOS |

**Test cases:** LO-MAC-FN-001, LO-MAC-FN-002

---

## UX 3-Second Test (critical screens)

| Screen | Where am I? | What should I do? | Why? | On tap? |
|--------|-------------|-------------------|------|---------|
| S05 TodayView | Tab + greeting | Tap hero CTA | Why-now line visible | Starts task/focus |
| S14 TaskListView | "Tasks" header | Complete or add | Priority badges | Row actions clear |
| S25 OnboardingView | Step X of Y | Next / Connect | Subtitle explains | Advances or skips |
| S30 EmergencyMode | "Emergency" | Breathe / simplify | Calming copy | Reduces options |
| S35 CycleDashboard | Phase name | Log or review | Insight card | Opens log sheet |

**Fail criteria:** Any question unanswered within 3 seconds at default Dynamic Type.

---

## Screen Test Case Summary Table

| ID | Screen | Priority | Type |
|----|--------|----------|------|
| LO-IOS-FN-001 | S05 | P0 | Hero refresh |
| LO-IOS-FN-005 | S06 | P1 | Card render |
| LO-IOS-FN-010 | S25 | P0 | Onboarding complete |
| LO-IOS-FN-019 | S19 | P1 | Brain dashboard load |
| LO-IOS-FN-029 | S29 | P1 | Module grid badges |
| LO-IOS-FN-040 | S30 | P0 | Emergency hides nav |
| LO-IOS-FN-045 | S08 | P0 | Capacity partial data |
| LO-IOS-A11Y-005 | S05 | P0 | Hero VoiceOver |
| LO-IOS-UX-005 | S05 | P0 | 3-second test |
| LO-IOS-PERF-014 | S14 | P1 | 500 task scroll |
| LO-WGT-FN-001 | S43 | P0 | Widget hero |
| LO-MAC-FN-001 | S46 | P1 | Productivity upload |

*Full module-level cases: [03-module-test-cases.md](03-module-test-cases.md)*
