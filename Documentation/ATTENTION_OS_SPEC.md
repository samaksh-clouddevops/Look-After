# FlowOS Attention OS — Canonical Specification

**Version:** 1.0  
**Status:** Single source of truth for product, design, and implementation  
**Codebase:** `LifeOS/` (packages: LookAfterCore, LookAfterAI, LookAfterData, LookAfterFeatures, LookAfterHealth)  
**Last updated:** July 2026

---

## How to Use This Document

This specification consolidates three prior design iterations into one authoritative reference:

1. **Base Specification** — UX strategy, design system, information architecture, accessibility
2. **Craft Specification** — Brand identity, physics-based motion, emotional adaptivity, micro-interactions
3. **Attention OS Specification (10/10)** — Proactive orchestration, living canvas, Flow World, zero-settings philosophy

When documents conflict, **this file wins**. Deprecated concepts are listed in [Appendix C](#appendix-c-deprecated-concepts).

---

## Table of Contents

1. [Product Vision](#1-product-vision)
2. [Glossary](#2-glossary)
3. [Product Philosophy](#3-product-philosophy)
4. [System Architecture](#4-system-architecture)
5. [Flow Director](#5-flow-director)
6. [Flow Canvas](#6-flow-canvas)
7. [Flow World](#7-flow-world)
8. [Behavior Memory](#8-behavior-memory)
9. [Environment Context](#9-environment-context)
10. [Flow Prediction](#10-flow-prediction)
11. [Flow Personality](#11-flow-personality)
12. [UX Strategy](#12-ux-strategy)
13. [Information Architecture](#13-information-architecture)
14. [User Flows](#14-user-flows)
15. [Design System — Flow Material v2](#15-design-system--flow-material-v2)
16. [Brand Identity](#16-brand-identity)
17. [Motion & Micro-Interactions](#17-motion--micro-interactions)
18. [Voice-First Interaction](#18-voice-first-interaction)
19. [Flow Presence (Not Chatbot)](#19-flow-presence-not-chatbot)
20. [Onboarding](#20-onboarding)
21. [Apple Ecosystem](#21-apple-ecosystem)
22. [Accessibility](#22-accessibility)
23. [Settings Philosophy](#23-settings-philosophy)
24. [Data Contracts](#24-data-contracts)
25. [Codebase Mapping](#25-codebase-mapping)
26. [Implementation Roadmap](#26-implementation-roadmap)
27. [Migration Strategy](#27-migration-strategy)

---

## 1. Product Vision

### One-Sentence Product

> **FlowOS is a calm operating system for your attention—it already knows what you should do next, and transforms to help you do it.**

### North Star Metric

**Meaningful tasks completed per week** — never daily active minutes, never screen time.

### The Defining Feature

**Proactive day orchestration via Flow Director.** FlowOS must not wait for the user to open the app. It quietly orchestrates the day using health, calendar, behavior, and environment signals—then surfaces a ready-to-start next action everywhere (phone, widget, Dynamic Island, Watch).

### Target Feeling

Users should feel: **Calm → Capable → Accomplished** (in that order, every session).

Opening FlowOS should feel like stepping into a calm, intelligent room—not launching a productivity app.

### Competitive Position

FlowOS is **not** Todoist + AI, Notion + timer, or Duolingo for tasks. It is:

**Apple Journal + Apple Health + Apple Fitness + Apple Intelligence + Arc Browser**, unified by one idea: *a calm operating system for your attention.*

---

## 2. Glossary

Canonical terminology. Use these names in product copy, new code, and documentation.

| Term | Definition |
|------|------------|
| **FlowOS** | User-facing product name |
| **Flow** | An immersive work session (replaces "Focus Session" in product copy) |
| **Flow Director** | Background orchestration engine; proactive day planner (evolves `ExecutiveBrain`) |
| **Flow Canvas** | Single living UI surface; states morph, no traditional navigation (evolves `LookAfterMasterCanvas`) |
| **Flow Surface** | Render model Flow Canvas consumes from Flow Director (hero task, briefing, button state) |
| **Flow World** | Living progress environment: Garden + River + Timeline (replaces XP/gamification) |
| **Flow Ring** | Circular timer/progress indicator during an active Flow |
| **Flow Window** | Predicted deep-work time block derived from calendar + energy |
| **Flow Prediction** | Pre-computed task, duration, and button label for the hero action |
| **Flow Personality** | UI temperament mode: Restore, Steady, or Peak (derived from energy) |
| **Behavior Memory** | On-device inference of user patterns (not chat history) |
| **Environment Context** | Fused real-world signals: health, calendar, weather, device state |
| **Flow** (presence) | The product voice/coach—ambient, never a chatbot character |
| **Anchor Mode** | Emergency overwhelm state: max 3 tasks, large tap targets (evolves Emergency Mode) |
| **Rest** | Break between Flows (replaces "Break" in product copy) |
| **Stack** | Task queue accessed via canvas gesture (evolves `TaskCardStackView`) |
| **Capture** | Voice/text quick-add (evolves `VoiceCaptureView`, `SpeechRecognitionManager`) |
| **Life Modules** | Secondary features: Finance, Meds, Travel, etc. (existing module system) |

### Codebase Names (During Migration)

Swift types may retain legacy names until refactored. Mapping:

| Product Term | Current Code |
|--------------|--------------|
| Flow Director | `ExecutiveBrain` → `FlowDirector` |
| Flow Canvas | `LookAfterMasterCanvas` → `FlowCanvasView` |
| Flow session state | `ADHDViewModel` → `FlowSessionController` (future) |
| Flow Surface | New type; fed by Flow Director |
| Design tokens | `DesignSystem` → `FlowDesignSystem` |

---

## 3. Product Philosophy

### Core Principles

| Principle | Meaning | ADHD Rationale |
|-----------|---------|----------------|
| **One Next Action** | Home shows one recommendation + one tap to start | Choice overload destroys executive function |
| **Orchestrate, Don't Ask** | Flow Director plans; user confirms or defers | Planning is highest-friction EF task |
| **Energy-First** | Schedule by capacity, not calendar alone | Time blindness + variable energy |
| **Gentle Recovery** | Streaks pause; distraction = re-entry, not failure | Shame spirals kill momentum |
| **Completion Over Engagement** | Celebrate closing, not opening | Avoid dopamine trap guilt cycles |
| **States, Not Screens** | Canvas morphs; no navigation stack for core flows | Context switches are costly |
| **Flow Learns** | Minimal settings; app adapts automatically | Configuration is executive load |
| **Growth, Not Points** | Flow World reflects life; no XP | Points feel generic and grind-oriented |

### What FlowOS Is NOT

- A todo list with badges
- A streak-shaming habit tracker
- A dashboard of metrics demanding interpretation
- A chatbot assistant with message threads
- Optimized for screen time or daily opens

### Emotional Design Contract

- Never optimize for engagement metrics
- Never use guilt language ("behind", "failed", "should have")
- Never punish rest—rest flourishes Flow World
- Max 2 proactive notifications per day
- Every interaction reduces decisions, not adds them

---

## 4. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      FLOW CANVAS (UI)                       │
│         Single view · state machine · morph transitions     │
├─────────────────────────────────────────────────────────────┤
│                      FLOW SURFACE                           │
│         Render model: briefing, hero task, button, world    │
├─────────────────────────────────────────────────────────────┤
│                      FLOW DIRECTOR                          │
│    Orchestration · day plan · rescheduling · predictions    │
├──────────────┬──────────────┬──────────────┬─────────────────┤
│  Behavior    │ Environment│ Flow World   │ Flow Session    │
│  Memory      │ Context    │ Engine       │ (timer/state)   │
├──────────────┴──────────────┴──────────────┴─────────────────┤
│                   EXECUTIVE BRAIN (AI Layer)                │
│         Natural language · task decomposition · copy        │
├─────────────────────────────────────────────────────────────┤
│  HealthKit · EventKit · WeatherKit · Core Motion · Siri    │
├─────────────────────────────────────────────────────────────┤
│  Widget · Live Activity · Dynamic Island · Watch · Mac      │
└─────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Owns | Does Not Own |
|-------|------|--------------|
| **Flow Canvas** | Visual states, morph animations, gestures | Business logic, AI calls |
| **Flow Surface** | Immutable snapshot for rendering | Timer tick, persistence |
| **Flow Director** | Orchestration, scheduling, predictions | UI layout |
| **Behavior Memory** | Pattern storage and inference | LLM calls |
| **Environment Context** | Signal fusion | Task CRUD |
| **Flow World Engine** | Garden/River/Timeline state | Task priority |
| **Executive Brain** | LLM copy, decomposition prompts | Background scheduling |
| **Flow Session** | Active timer, pause/resume, Live Activity | Day planning |

---

## 5. Flow Director

**Priority: D2 — build first.** This is the product's foundation.

### Purpose

Flow Director continuously maintains a living day plan and publishes a `FlowSurface` snapshot. It runs proactively—not when the user opens the app.

### Trigger Schedule

| Trigger | Action |
|---------|--------|
| Every 15 minutes (background) | Re-evaluate day plan |
| Health sync complete | Adjust energy, reschedule |
| Calendar change (EventKit) | Recalculate Flow Window, hero task |
| Task completed/deferred | Update stack, select next hero |
| Location significant change | Context-aware task filtering |
| App foreground | Refresh surface immediately |
| Flow session end | Predict next action |

### Inputs

```swift
// Conceptual — see §24 Data Contracts for protocol shapes
FlowDirectorInput {
    cognitiveSnapshot: CognitiveSnapshot      // existing
    healthSummary: HealthSummary?            // existing
    pendingTasks: [LifeTask]                 // existing
    recentProductivity: [ProductivitySession] // existing
    calendarEvents: [CalendarEvent]          // EventKit
    behaviorMemory: BehaviorMemorySnapshot   // new
    environmentContext: EnvironmentContext    // new
    activeFlowSession: FlowSessionState?     // from ADHDViewModel
    currentTime: Date
}
```

### Outputs (`FlowSurface`)

```swift
FlowSurface {
    // Briefing (proactive copy)
    greeting: String                          // "Good morning, Sam."
    briefingLines: [String]                  // max 3 lines
    flowPersonality: FlowPersonality         // Restore | Steady | Peak

    // Hero action
    heroTask: LifeTask?
    prediction: FlowPrediction

    // Context chips
    flowWindow: DateInterval?                 // "Best deep work: 10:00–12:30"
    nextCalendarEvent: CalendarEvent?
    energyScore: Double
    focusReadiness: Double

    // Orchestration transparency (optional expand)
    rescheduledTasks: [RescheduleNotice]    // "Moved Design to after lunch"
    coachMoment: CoachMoment?                // behavioral suggestion chip

    // World peek
    worldSnapshot: FlowWorldPeek

    // Metadata
    generatedAt: Date
    confidence: Double
}
```

### Orchestration Rules

| Signal | Flow Director Action |
|--------|---------------------|
| Meeting in <45 min | Surface task ≤30 min or suggest Rest |
| HRV below 7-day baseline | Defer high-energy tasks to predicted recovery window |
| Task deferred ≥3 times | Emit `CoachMoment`: offer micro-chunk breakdown |
| In-progress task exists | Button label: **Continue** (not Start) |
| Calendar gap ≥90 min | Label as Flow Window; prefer deep-work task |
| Detected pattern (Behavior Memory) | Pre-select task type and duration |
| Rain + no meetings | Briefing: deep-work framing; cooler ambience |
| Battery <20% | Shorten default Flow duration |
| Low Power Mode | Suppress mesh animation flag on surface |

### Morning Briefing Example

```
Good morning, Sam.

Your HRV is higher than usual.
Team sync starts in 45 minutes.

I moved "Architecture Design" to after lunch—it needs deep focus.

▶ Continue API Review
  18 minutes · Ready now

Best deep work window today: 10:00–12:30
```

### Proactive Surfaces (User May Never Open App)

| Surface | When | Content |
|---------|------|---------|
| Lock Screen Widget | 7–9 AM | Briefing + Start/Continue button |
| Dynamic Island | Active Flow | Task, timer, progress, controls |
| Notification (≤2/day) | High-confidence window | Single sentence + action |
| Apple Watch | Energy shift detected | Brief suggestion |
| Siri | "Hey Flow, what's next?" | Speaks orchestrated plan |

### AI Role in Flow Director

LLM (`GeminiProvider` via `LookAfterPrompts`) generates **natural language only**:

- Briefing copy
- Coach moment copy
- Reschedule explanations

**Flow Director owns all decisions** (which task, what duration, when to reschedule). AI does not choose tasks—it explains Flow Director's choices warmly.

### Implementation Notes

- Evolve `ExecutiveBrain`; do not rewrite from scratch
- Extract scheduling logic into pure functions (testable without LLM)
- `FlowDirector` publishes `@Published var surface: FlowSurface`
- Background execution via `BGAppRefreshTask` + foreground triggers
- Widget/Live Activity read `FlowSurface` via App Groups (`WidgetDataStore`)

---

## 6. Flow Canvas

**Priority: D1 — build after Flow Director provides stable `FlowSurface`.**

### Purpose

One living canvas. Cards become timers. Timers become celebrations. Celebrations become the next task. **No screen changes for core flows—only transformations.**

### Canvas State Machine

```
                    ┌──────────┐
         ┌─────────│  AMBIENT │─────────┐
         │         └──────────┘         │
         │    (idle, ambient motion)   │
         ▼                               ▼
   ┌──────────┐                   ┌──────────┐
   │  BRIEF   │                   │  REST    │
   │ (morning │                   │ (break,  │
   │  intel)  │                   │  low en) │
   └────┬─────┘                   └────┬─────┘
        │                              │
        ▼                              │
   ┌──────────┐                        │
   │   NOW    │◄───────────────────────┘
   │ (hero +  │
   │  action) │
   └────┬─────┘
        │ Start / Continue
        ▼
   ┌──────────┐
   │   FLOW   │
   │ (timer,  │
   │immersive)│
   └────┬─────┘
        │ Complete
        ▼
   ┌──────────┐      ┌──────────┐
   │ CELEBRATE│─────►│   NOW    │ (next task rises)
   └──────────┘      └──────────┘
```

### Secondary States (Gesture Access)

| State | Gesture | Replaces |
|-------|---------|----------|
| **Stack** | Swipe up | `TaskCardStackView`, task list sheet |
| **World** | Swipe down | Flow Garden full view |
| **Timeline** | Pinch out | `InsightsDashboardView` charts |
| **Capture** | Long press | `VoiceCaptureView` FAB |
| **Anchor** | Shake | `EmergencyModeView` |

### Morph Rules (NOW → FLOW)

- Same view hierarchy; `matchedGeometryEffect` on: task title, action button, energy ring → Flow Ring
- Tab bar and legacy header: fade + slide (until legacy nav removed)
- Background mesh intensity: 0.3 → 0.7
- Duration: 0.8s, `flowSpring` curve
- **No `NavigationStack` push** for Flow entry

### Spatial Depth (Z-Order)

| Layer | Z | Parallax Rate |
|-------|---|---------------|
| Hero action button | +3 | 1.0× |
| Task card | +2 | 1.0× |
| Briefing text | +1 | 0.6× |
| Flow Ring / energy ring | 0 | 0.4× |
| Flow World peek | -1 | 0.2× |
| Mesh gradient | -2 | 0.1× |
| Grain texture | -3 | fixed |

Card tilt via Core Motion: ±5° max. Disabled in Restore personality, Anchor Mode, and Reduce Motion.

### Migration Requirement

**Do not remove existing navigation until Flow Canvas reaches feature parity.**

During migration, `LookAfterMasterCanvas` coexists: legacy sheets/buttons remain reachable while Flow Canvas states are built incrementally. Remove legacy nav only when:

- [ ] NOW, FLOW, CELEBRATE states stable
- [ ] Stack gesture matches `TaskCardStackView` functionality
- [ ] Capture voice/text works
- [ ] Anchor Mode accessible
- [ ] Settings accessible (minimal sheet)
- [ ] Life Modules reachable

---

## 7. Flow World

**Replaces all XP, levels, streak counters, and traditional gamification.**

### Purpose

Emotionally memorable progress—a living world the user stewards, not points they earn.

### Three Layers

#### 7.1 Flow Garden

Each life area / project grows a distinct plant:

| Life Area | Plant | Grows When |
|-----------|-------|------------|
| Creative | Cherry blossom | Creative Flow sessions complete |
| Work / Code | Bamboo | Deep work tasks complete |
| Learning | Fern | Study/reading tasks complete |
| Health | Succulent | Health-related tasks complete |
| Social | Wildflowers | Social tasks complete |
| Admin | Moss | Quick admin wins complete |

**Rules:**
- Growth on **completion only**—never on app opens
- Plants **never wilt**—they pause during absence, resume on return
- Rest days trigger **flourish** animation (water, brighter colors)
- Recovery after distraction **strengthens** nearest plant
- No numeric levels exposed to user

Access: swipe down on Flow Canvas → World state.

#### 7.2 Flow River

- Each completed task releases a glowing particle into a river strip on the NOW canvas
- River brightness = cumulative Flow depth for the week (replaces "focus score" visualization)
- No numbers by default—light and movement only
- Pinch river → gentle week labels (not bar charts)

#### 7.3 Memory Timeline

- Cinematic vertical timeline replacing analytics charts
- Auto-generated from completions and Flow sessions
- Emoji moments chosen by Flow (not user)
- Pinch out from NOW → Timeline state

**Example entry:**
```
Monday
  🌱  Started first Flow
       ↓
  ☀️  Finished Design doc
       ↓
  🌙  Chose rest intentionally
```

### Progress Without Guilt

| Event | Flow World Response |
|-------|---------------------|
| Task complete | Particle → river; relevant plant grows |
| Deep Flow (≥45 min) | River segment brightens |
| Distraction recovery | Plant pulse "strengthen" |
| Rest day chosen | Garden flourish animation |
| Long absence | Plants pause (no decay) |

---

## 8. Behavior Memory

### Purpose

On-device behavioral inference. Flow becomes a **coach**, not an assistant with chat history.

### Stores (Local Only)

| Category | Example | Use |
|----------|---------|-----|
| Completion patterns | "Documentation faster with music" | Coach moment before Flow |
| Deferral patterns | "Design deferred 3×" | Auto-offer micro-chunks |
| Energy correlations | "Deep work best 10–12 when HRV >50" | Flow Window prediction |
| Duration accuracy | "Estimates 30 min, actually 45" | Flow Prediction adjustment |
| Recovery patterns | "Returns after distraction in ~8 min" | Re-entry copy timing |
| Context preferences | "Voice capture used mornings" | Default Capture mode |

### Does NOT Store

- Chat threads as primary memory
- User-selected "coach tone" or "ADHD type" settings
- Cross-user or cloud behavioral data (unless explicit opt-in sync later)

### Coach Moments (Not Chat)

Ephemeral UI chips on Flow Canvas—never a message thread:

```
You've postponed "Design" three times.
[ Break into 5-min chunks ]  [ Skip ]
```

```
You finish documentation faster with music.
[ Start Focus playlist ]  [ Not now ]
```

### Implementation

- New `BehaviorMemoryStore` in `LookAfterData`
- Nightly on-device analysis (rule-based first; ML optional later)
- Feeds `FlowDirector` and `LookAfterPrompts` context
- Deprecate `ExecutiveBrain.chatHistory` as primary UX (see §19)

---

## 9. Environment Context

Single fused struct, recomputed on Flow Director triggers:

```swift
EnvironmentContext {
    // Health (HealthKit via HealthSyncService)
    energyScore: Double
    hrvDelta: Double              // vs 7-day baseline
    sleepQuality: SleepQuality

    // Calendar (EventKit)
    nextEvent: CalendarEvent?
    freeBlockMinutes: Int
    flowWindow: DateInterval?

    // World (WeatherKit)
    weather: WeatherCondition
    timeOfDay: TimeOfDay
    isWeekend: Bool

    // Device
    focusModeEnabled: Bool
    batteryLevel: Float
    isLowPowerMode: Bool
    reduceMotionEnabled: Bool

    // Optional (permission-gated)
    ambientNoiseLevel: NoiseLevel?
    locationContext: LocationContext?   // home | office | commute
}
```

### Fusion → Adaptation

| Fused Signal | Response |
|--------------|----------|
| Rain + free morning | Deep-work briefing; cooler mesh |
| Office + meetings day | Admin/light tasks prioritized |
| iOS Focus Mode: Work | Work tasks only on surface |
| Noise >70 dB | Shorter Flow suggestion |
| Night + low brightness | Force Restore personality |
| Commute detected | Audio-friendly tasks surfaced |

All automatic—no user toggles.

---

## 10. Flow Prediction

Pre-computed hero action. User should rarely choose duration or task manually.

```swift
FlowPrediction {
    suggestedTask: LifeTask
    suggestedDurationMinutes: Int
    buttonLabel: String           // "Continue API Review" | "Start Deep Flow"
    buttonSubtitle: String        // "18 minutes · Ready now"
    confidence: Double            // 0.0–1.0
    reasoning: String             // for briefing, not settings UI
    actionType: FlowActionType    // .continue | .start | .startDeep | .startSmall | .tryMicro
}
```

### Button Label Examples

| Condition | Label |
|-----------|-------|
| In-progress task | `Continue API Review · 18 min` |
| High-confidence pattern | `Start Deep Flow · 95 min · Ready` |
| Low energy | `Start something small · 10 min` |
| Post-deferral | `Try a 5-min start on Design?` |
| Default | `Start Flow · 25 min` |

Long-press hero button → alternatives sheet (override, not default).

---

## 11. Flow Personality

UI temperament derived from `energyScore` + sleep + time of day. Replaces manual theme/animation settings.

| Mode | Energy | Motion Tempo | Copy Tone | Visual |
|------|--------|--------------|-----------|--------|
| **Restore** | 0–35% | 1.3× slower | Gentle, validating | Rose/apricot aura, softer contrast |
| **Steady** | 36–65% | Standard | Calm, matter-of-fact | Amber aura |
| **Peak** | 66–100% | 0.85× faster | Confident | Cyan/violet aura, larger Flow Ring |

Restore mode: max 2 tasks visible, card tilt disabled, sounds off by default, body text +1pt.

Inject via `@Environment(\.flowPersonality)`.

---

## 12. UX Strategy

### Primary Personas

**Alex (28, ADHD-Inattentive)** — Can't start. Needs zero-decision entry and visible micro-steps.

**Jordan (35, Anxiety + Executive Dysfunction)** — Overwhelmed by lists. Needs AI curation and permission to do less.

**Sam (22, Hyperfocus-prone)** — Forgets breaks, crashes. Needs gentle session boundaries.

### Jobs To Be Done

1. **Help me start** — Zero-decision entry
2. **Help me stay** — Immersive Flow with ambient support
3. **Help me return** — Fast re-entry after interruption
4. **Help me feel okay** — Progress without guilt
5. **Plan for me** — Flow Director handles sequencing

---

## 13. Information Architecture

### Target IA (Post-Migration)

Single Flow Canvas with gesture-accessed states. No tab bar.

| Access | Content | Legacy Equivalent |
|--------|---------|-------------------|
| NOW (default) | Hero task, briefing, action | `LookAfterMasterCanvas` center |
| FLOW | Immersive timer | `FocusSessionView` |
| Stack (swipe up) | Task queue | `TaskCardStackView` |
| World (swipe down) | Flow Garden | New |
| Timeline (pinch out) | Memory Timeline | `InsightsDashboardView` |
| Capture (long press) | Voice/text add | `VoiceCaptureView` |
| Life (sheet from profile) | Secondary modules | `AllModulesGridView` |
| Settings (profile avatar) | Account + privacy only | `SettingsView` (reduced) |

### Life Modules (Grouped)

```
Life
├── Mind & Body    — Journal, Meditation, Medication, Health
├── Work & Learning — Learning Hub, Creativity, Calendar
├── Home & Money   — Finance, Bills
└── World          — Travel, Social, Goals
```

80% of sessions never leave NOW / FLOW / CELEBRATE states.

### Depth Model

```
Level 0: NOW     — 1 task, 1 button
Level 1: FLOW    — Timer immersion
Level 2: Stack   — Swipeable queue
Level 3: Life    — Infrequent modules
Level 4: Settings — Rare
```

---

## 14. User Flows

### A. Morning (Proactive — Primary)

```
7:30 AM  Health sync completes (background)
7:31 AM  Flow Director publishes FlowSurface
7:31 AM  Widget updates: briefing + Continue/Start button
8:42 AM  User opens app → NOW state already populated
         User taps hero button → FLOW morph (0.8s)
         User completes → CELEBRATE → NOW (next task rises)
```

### B. Capture → Flow

```
Long press → Capture sheet → voice/text
         → AI parses (TaskDecomposer)
         → "Start now?" / "Add to stack"
         → Optional immediate FLOW morph
```

### C. Distraction Recovery

```
Flow interrupted → Live Activity persists
                → User returns → "Welcome back" (0.5s)
                → Micro-step reminder → Resume (1 tap)
                → No streak penalty
```

### D. Overwhelm (Anchor Mode)

```
Shake / Siri "I'm overwhelmed" / long-press Anchor
         → Max 3 tasks, 56pt targets
         → Solid background, no gradients
         → "Just pick one. That's all."
```

### E. End of Day

```
Timeline gesture → day's moments
                → Optional 30s voice reflection
                → Tomorrow preview (1 sentence from Flow Director)
                → No "you missed X" messaging
```

---

## 15. Design System — Flow Material v2

Evolves `DesignSystem.swift` in LookAfterCore.

### Color Tokens

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `flow.background.primary` | `#F7F5F2` | `#0D0F14` | Root |
| `flow.background.secondary` | `#FFFFFF` | `#161922` | Cards |
| `flow.text.primary` | `#1A1A1E` | `#F5F4F2` | Headlines |
| `flow.text.secondary` | `#6B6B70` | `#A8A8AE` | Body |
| `flow.accent.primary` | `#5B6CFF` | `#5B6CFF` | Hero action |
| `flow.accent.secondary` | `#3DD6C6` | `#3DD6C6` | Success, high energy |
| `flow.accent.warm` | `#FF9F5A` | `#FF9F5A` | Warmth, rest |
| `flow.accent.glow` | `#C084FC` | `#C084FC` | Flow presence, AI |

Personality auras overlay on background (see §11).

### Surface Stack (Cards)

```
Layer 5: Content
Layer 4: Inner highlight (white @ 4% top edge)
Layer 3: Glass (.ultraThinMaterial + tint)
Layer 2: Border (1pt gradient stroke)
Layer 1: Shadow (dual: tight + ambient)
Layer 0: Accent glow (@ 8%, blur 40pt)
```

### Grain

2% monochromatic noise tile, `blendMode: .overlay`, `opacity: 0.025`. Eliminates gradient banding.

### Typography

| Style | Font | Size | Use |
|-------|------|------|-----|
| `flow.display.hero` | SF Pro Rounded | 34pt Bold | Task title in FLOW |
| `flow.display.large` | SF Pro Rounded | 28pt Semibold | Greeting |
| `flow.title.1` | SF Pro Rounded | 22pt Semibold | Card titles |
| `flow.body` | SF Pro | 17pt Regular | Briefing |
| `flow.caption` | SF Pro | 13pt Medium | Metadata |
| `flow.label` | SF Pro | 11pt Bold | Labels (tracking +0.5) |
| `flow.timer` | SF Mono | 56pt Medium | Flow Ring countdown |

Dynamic Type required on all styles. Optional OpenDyslexic override in accessibility.

### Spacing (8pt Grid)

`4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64`

### Corner Radius

`8 · 12 · 16 · 20 · 24 · full (pill)`

---

## 16. Brand Identity

### Motif: The Flow Wave

Continuous sine-wave path representing energy through time. Used in: app icon, Flow Ring stroke, loading states, XP float path (deprecated—river particles), Dynamic Island compact icon.

### Custom Icon Set: Flow Glyphs

12 custom glyphs (24×24, 2pt stroke, rounded caps) supplement SF Symbols:

`flow.start` · `flow.wave` · `flow.stack` · `flow.pulse` · `flow.capture` · `flow.defer` · `flow.complete` · `flow.return` · `flow.rest` · `flow.anchor` · `flow.presence` · `flow.milestone`

### Signature Animation: Liquid Spring

```swift
// Canonical
Animation.spring(response: 0.52, dampingFraction: 0.78, blendDuration: 0.12)

// Completion collapse
Animation.spring(response: 0.62, dampingFraction: 0.68)

// Ambient breathe
Animation.easeInOut(duration: 4.2).repeatForever(autoreverses: true)
```

**Signature 3-beat:** Compress (0.92) → Glow burst → Spring to rest.

### Sound Palette (Optional)

| Event | Character |
|-------|-----------|
| Start Flow | Soft ascending breath, 0.6s |
| Flow complete | Warm two-note chime, 0.8s |
| Task complete | Soft tick + shimmer, 0.3s |
| Level milestone | Gentle swell, 1.2s |
| Capture saved | Water drop, 0.2s |

All below -20 LUFS. Off by default in Restore personality.

### Illustration Style

Soft contours, 2pt line weight, max 2 colors. Empty states, onboarding, milestones. Never: stressed figures, clock wings, productivity clichés.

---

## 17. Motion & Micro-Interactions

### Philosophy

> Motion is punctuation, not decoration. Every animation answers: where am I, what changed, what next?

### Ambient Motion (NOW State)

| Element | Behavior | Period |
|---------|----------|--------|
| Mesh background | Control points drift | 20s |
| Flow Ring / energy ring | Shimmer travels | 8s |
| Task card | Float Y ±2pt | 6s |
| Hero button | Glow breathe 0.15↔0.35 | 4.2s |
| Flow River | Particles drift | continuous |

All disabled with Reduce Motion or Low Power Mode (glow breathe may continue).

### Choreographed Moments

#### Start / Continue Flow

```
T+0.0s  Press: scale 0.96, glow intensify, haptic .soft
T+0.1s  Release: glow ripple 120pt, haptic .medium
T+0.15s Button morphs → Flow Ring (matchedGeometry)
T+0.3s  Legacy chrome fades (tab/header if present)
T+0.4s  Task card expands; title scales up
T+0.6s  Ring trim draws; haptic .success
T+0.8s  FLOW state active
```

#### Task Complete (Liquid Collapse)

```
T+0.0s  Card squash: scaleY 0.85, scaleX 1.05
T+0.15s Checkmark trim draw
T+0.2s  Glow burst from center
T+0.3s  Card opacity → 0; particle → Flow River
T+0.35s Plant grow animation (if applicable)
T+0.4s  Next card rises (liquid spring)
T+0.5s  haptic .success
```

No horizontal fly-off—vertical collapse = settling, not rejection.

#### Distraction Recovery

```
T+0.0s  Foreground during active Flow
T+0.0s  "Welcome back" fade in (0.3s)
T+0.5s  Fade out; micro-step reminder
T+1.0s  Controls pulse once; haptic .soft
```

### Dynamic Island (Flow Active)

**Compact:** `∿ 18m  ████████░░` (wave icon + time + progress bar)

**Expanded:** Task title, timer, progress, `[ Rest ] [ Done ] [ +5m ]`

Interactive via App Intents wired to `ADHDViewModel` (future: `FlowSessionController`).

Update `FocusLiveActivity.swift` and `FlowActivityAttributes.ContentState` with `progressFraction`.

### Haptic Map

| Action | Haptic |
|--------|--------|
| Tab/gesture select | `.selection` |
| Hero button tap | `.medium` |
| Task complete | `.success` |
| Defer | `.light` |
| Timer last 10s | `.light` each second (optional) |
| Anchor enter | `.warning` |

---

## 18. Voice-First Interaction

Typing is fallback. Voice is primary.

### Siri / App Intents

| Command | Response |
|---------|----------|
| "Hey Flow, I'm overwhelmed" | Anchor Mode + one task suggestion |
| "Hey Flow, what's next?" | Speaks `FlowSurface` briefing |
| "Hey Flow, capture: …" | Parses → stack → optional start |
| "Hey Flow, I need a break" | REST state; garden flourish |
| "Hey Flow, not today" | Defers hero; refreshes surface |

### In-App

Long-press anywhere on Flow Canvas → voice capture (`SpeechRecognitionManager`). Waveform first; text field second.

---

## 19. Flow Presence (Not Chatbot)

Flow is a **presence**—not AI, not assistant, not chatbot.

### Voice Rules

| Never | Always |
|-------|--------|
| "I'm an AI assistant" | "Flow thinks this is a good time for Design" |
| "Based on your data…" | "Your energy is high this morning" |
| Long explanations | One sentence + action |
| Chat threads | Briefing lines + coach moment chips |

### Visual

Soft lilac orb (`#C084FC` @ 20%). Pulses when Flow Director is computing. Absent during FLOW state.

### Deprecation

- `AICoachView` chat UI → deprecated; remove after Flow Canvas ships briefing + coach moments
- `ExecutiveBrain.chatHistory` → not primary UX
- Settings: `aiCoachTone`, `adhdFocusChallenge` → inferred by Behavior Memory, removed from settings UI

---

## 20. Onboarding

Apple Watch–style ritual. Auth is step 6, not step 1.

| Step | Screen | Purpose |
|------|--------|---------|
| 1 | Welcome | "Let's build a life that works with your brain." |
| 2 | Philosophy | 3 auto-advancing statements (reduce friction, not discipline) |
| 3 | Health | HealthKit permission; skip allowed |
| 4 | Calendar | EventKit permission; skip allowed |
| 5 | Voice | Live demo capture; skip allowed |
| 6 | Account | Apple / Google / Guest |
| 7 | First Flow | AI suggests one task; user completes first Flow |

Total: 90–120 seconds. Mesh breathe begins on step 1.

Evolves `AuthView`—does not replace auth logic in `FirebaseManager`.

---

## 21. Apple Ecosystem

One continuous experience across surfaces:

| Surface | Primary Job |
|---------|-------------|
| iPhone Flow Canvas | Orchestrated NOW + FLOW |
| Home Screen Widget | Start/Continue without opening app |
| Lock Screen Widget | Briefing + action |
| Dynamic Island | Active Flow control |
| Live Activity | Full Flow state on lock screen |
| Apple Watch | Start / pause / complete (3 actions max) |
| Watch Complication | Next task + energy dot |
| Mac Menu Bar | Active Flow timer (future) |
| Siri / Shortcuts | Voice commands, automations |
| visionOS | Spatial Flow Room (future) |

**Continuity rule:** Flow session state in App Groups; all surfaces read same `FlowSurface` + session snapshot. Never desync timer.

Existing integration points: `WidgetSyncService`, `LiveActivityManager`, `WidgetDataStore`, `FlowActivityAttributes`.

---

## 22. Accessibility

Built-in, not retrofitted.

| Need | Implementation |
|------|----------------|
| ADHD | One hero action, defer always available, Anchor Mode |
| Autism | Reduce Motion, predictable layouts, no surprise modals |
| Dyslexia | OpenDyslexic option, line spacing, no ALL CAPS body |
| Color blindness | Icon + label on all states |
| Voice Control | Named actions: "Start Flow", "Complete task" |
| Dynamic Type | All text scales; hero button grows vertically |
| Reduce Motion | Crossfade only; no parallax/tilt/particles |
| VoiceOver | Order: Briefing → Task → Action; swipe action hints |

---

## 23. Settings Philosophy

Flow learns. Users live.

### Remaining Settings

```
Profile      — Name, sign in/out
Privacy      — Health, Calendar, Microphone, Delete data
Advanced     — Gemini API key (hidden; 7-tap on version)
```

### Removed → Auto-Adaptive

| Old Setting | Replaced By |
|-------------|-------------|
| Theme | System + time-of-day |
| Animation speed | Flow Personality |
| Focus duration | Flow Prediction + Behavior Memory |
| Peak hours | Flow Director + calendar |
| Coach tone | Behavior Memory inference |
| Notification prefs | Max 2/day high-confidence |
| ADHD challenge type | Deferral/completion inference |
| Pin to lock screen | Auto on Flow start |

Current `SettingsView` reduced incrementally; do not delete until replacements exist.

---

## 24. Data Contracts

Protocol-driven contracts for D2 implementation. Types live in `LookAfterCore` unless noted.

### FlowPersonality

```swift
public enum FlowPersonality: String, Codable, Sendable {
    case restore  // energy 0.0–0.35
    case steady   // energy 0.35–0.65
    case peak     // energy 0.65–1.0
}
```

### FlowActionType

```swift
public enum FlowActionType: String, Codable, Sendable {
    case `continue`
    case start
    case startDeep
    case startSmall
    case tryMicro
}
```

### FlowPrediction

```swift
public struct FlowPrediction: Codable, Sendable, Equatable {
    public var taskID: UUID
    public var suggestedDurationMinutes: Int
    public var buttonLabel: String
    public var buttonSubtitle: String
    public var confidence: Double
    public var reasoning: String
    public var actionType: FlowActionType
}
```

### RescheduleNotice

```swift
public struct RescheduleNotice: Codable, Sendable, Identifiable {
    public var id: UUID
    public var taskID: UUID
    public var taskTitle: String
    public var explanation: String   // "Moved to after lunch—needs deep focus"
}
```

### CoachMoment

```swift
public struct CoachMoment: Codable, Sendable, Identifiable {
    public var id: UUID
    public var message: String
    public var primaryAction: String   // "Break into 5-min chunks"
    public var secondaryAction: String // "Skip"
    public var momentType: CoachMomentType
}

public enum CoachMomentType: String, Codable, Sendable {
    case microChunkOffer
    case playlistOffer
    case restSuggestion
    case deferralPattern
}
```

### FlowWorldPeek

```swift
public struct FlowWorldPeek: Codable, Sendable {
    public var riverBrightness: Double    // 0.0–1.0
    public var activePlantStages: [String: Int]  // lifeArea → stage 0–10
    public var todayParticleCount: Int
}
```

### FlowSurface

```swift
public struct FlowSurface: Codable, Sendable {
    public var greeting: String
    public var briefingLines: [String]
    public var flowPersonality: FlowPersonality
    public var heroTask: LifeTask?
    public var prediction: FlowPrediction?
    public var flowWindow: DateInterval?
    public var nextCalendarEvent: CalendarEventReference?
    public var energyScore: Double
    public var focusReadiness: Double
    public var rescheduledTasks: [RescheduleNotice]
    public var coachMoment: CoachMoment?
    public var worldPeek: FlowWorldPeek
    public var generatedAt: Date
    public var confidence: Double
}
```

### FlowDirectorProtocol

```swift
@MainActor
public protocol FlowDirectorProtocol: ObservableObject {
    var surface: FlowSurface { get }
    var isOrchestrating: Bool { get }
    func orchestrate() async
    func handleTaskCompleted(_ task: LifeTask) async
    func handleTaskDeferred(_ task: LifeTask) async
    func handleFlowSessionEnded(durationMinutes: Int) async
}
```

### BehaviorMemoryStoreProtocol

```swift
public protocol BehaviorMemoryStoreProtocol {
    func recordCompletion(task: LifeTask, durationMinutes: Int, context: EnvironmentContext) async
    func recordDeferral(task: LifeTask) async
    func snapshot() async -> BehaviorMemorySnapshot
}
```

### EnvironmentContextProviderProtocol

```swift
public protocol EnvironmentContextProviderProtocol {
    func currentContext() async -> EnvironmentContext
}
```

### CalendarEventReference

Lightweight EventKit bridge (avoid EventKit in LookAfterCore):

```swift
public struct CalendarEventReference: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var minutesUntilStart: Int
}
```

---

## 25. Codebase Mapping

| Spec Component | Current File | Target |
|----------------|--------------|--------|
| Flow Director | `ExecutiveBrain.swift` | `FlowDirector.swift` (LookAfterAI) |
| AI prompts | `LookAfterPrompts.swift` | Add `flowBriefingPrompt`, `coachMomentPrompt` |
| Flow Canvas | `LookAfterMasterCanvas.swift` | `FlowCanvasView.swift` |
| Flow session | `ADHDViewModel.swift` | Keep; rename later |
| Flow UI (timer) | `FocusSessionView` in `ADHDViews.swift` | Morph into canvas FLOW state |
| Task stack | `TaskCardStackView.swift` | Stack canvas state |
| Tasks CRUD | `TasksViewModel.swift` | Unchanged; Flow Director reads |
| Health | `HealthSyncService.swift`, `HealthManager.swift` | Feeds Environment Context |
| Widgets | `WidgetSyncService.swift`, `LookAfterWidget/` | Read `FlowSurface` |
| Live Activity | `LiveActivityManager.swift`, `FocusLiveActivity.swift` | Flow branding + progress |
| Voice | `SpeechRecognitionManager.swift` | Capture gesture |
| Design tokens | `DesignSystem.swift` | `FlowDesignSystem.swift` |
| Empty states | `EmptyStateView.swift` | Illustrated variants |
| Auth/Onboarding | `AuthView.swift` | 7-step ritual shell |
| Settings | `SettingsView.swift` | Reduced to §23 |
| Coach chat | `AICoachView.swift` | Deprecated |
| Insights | `InsightsDashboardView.swift` | Replaced by Timeline state |
| Emergency | `EmergencyModeView` | Anchor state |
| Activity attrs | `FlowActivityAttributes.swift` | Add `progressFraction` |

---

## 26. Implementation Roadmap

Build in order. **Stop after each milestone for approval.**

### Phase 0 — Specification ✅

- [x] Unified `FlowOS/ATTENTION_OS_SPEC.md`

### Phase D2 — Flow Director (NEXT)

**Goal:** Proactive orchestration engine + data contracts + morning briefing.

| Milestone | Deliverable | Compiles |
|-----------|-------------|----------|
| D2.1 | Data contracts in `LookAfterCore` (`FlowSurface`, `FlowPrediction`, etc.) | ✅ |
| D2.2 | `BehaviorMemoryStore` stub (empty snapshot) | ✅ |
| D2.3 | `EnvironmentContextProvider` (health + calendar + time) | ✅ |
| D2.4 | `FlowDirector` pure scheduling logic (no LLM) | ✅ |
| D2.5 | LLM briefing integration via `ExecutiveBrain`/`LookAfterPrompts` | ✅ |
| D2.6 | `WidgetSyncService` publishes `FlowSurface` | ✅ |
| D2.7 | Unit tests for scheduling rules | ✅ |

**Does not change UI yet.** `LookAfterMasterCanvas` may optionally display `FlowSurface` briefing.

### Phase D1 — Flow Canvas

**Goal:** State machine + morph transitions. Legacy nav coexists.

| Milestone | Deliverable |
|-----------|-------------|
| D1.1 | `FlowCanvasView` shell + NOW state rendering `FlowSurface` |
| D1.2 | FLOW morph from NOW (matchedGeometry) |
| D1.3 | CELEBRATE → NOW transition |
| D1.4 | Stack gesture state (wrap `TaskCardStackView`) |
| D1.5 | Anchor, Capture, REST states |
| D1.6 | Feature parity checklist → remove legacy nav |

### Phase D3 — Flow Prediction + Hero Button

Predictive labels; Continue vs Start logic.

### Phase D4 — Behavior Memory (Full)

Pattern inference, coach moments.

### Phase D5 — Environment Fusion

WeatherKit, Focus Mode, noise (optional).

### Phase D6 — Flow World

Garden, River, Timeline engines.

### Phase D7 — Deprecation Pass

Remove XP references, chat coach UI, settings bloat.

### Phase D8 — Voice-First + Siri Intents

### Phase D9 — Proactive Surfaces

Lock screen briefing widget, notification policy.

### Phase D10 — Craft Polish

Spatial depth, sound, onboarding ritual, Flow Material v2 tokens.

---

## 27. Migration Strategy

### Principles

1. **Compile after every milestone**
2. **Reuse and refactor—never big-bang rewrite**
3. **Legacy UI until parity**
4. **Protocol-driven new code** for testability
5. **App Groups for surface sync** from day one of D2

### Flow Director Migration from ExecutiveBrain

```
ExecutiveBrain (keep)
    ├── chat()           → deprecate gradually
    ├── getNextAction()  → absorbed by FlowDirector.orchestrate()
    └── lastSnapshot     → FlowDirector publishes via FlowSurface

FlowDirector (new)
    ├── uses ExecutiveBrain for LLM copy only
    ├── owns scheduling rules
    └── publishes FlowSurface
```

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Background orchestration limits | Foreground refresh + push widget update on health sync |
| LLM latency | Show rule-based surface immediately; refresh copy async |
| Feature regression during D1 | Legacy sheets remain until checklist complete |
| EventKit privacy | Calendar optional; Flow Director degrades gracefully |

---

## Appendix A — Design Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Navigation | Gesture canvas states, not tabs | 10/10 spec; tabs are legacy during migration |
| Gamification | Flow World only | XP generic; garden/river/timeline match philosophy |
| Coach UX | Flow presence, not chat | Reduces cognitive load; avoids ChatGPT pattern |
| Settings | Minimal auto-adaptive | Apple philosophy; Flow learns |
| AI role | Copy only; Director decides | Prevents hallucinated scheduling |
| Product name | FlowOS | Already in `AuthView`; codebase stays LifeOS until rename |
| Session name | Flow | Not Focus Session |
| Break name | Rest | Calmer connotation |

---

## Appendix B — Motion Token Reference

| Token | Value | Use |
|-------|-------|-----|
| `flowSpring` | response 0.52, damping 0.78 | Default |
| `flowLiquid` | response 0.62, damping 0.68 | Completions |
| `flowBreathe` | 4.2s easeInOut repeat | Ambient glow |
| `flowInstant` | 0.15s easeOut | Press |
| `flowQuick` | 0.25s spring(0.35, 0.85) | Gestures |
| `flowEmphasis` | 0.6s spring(0.5, 0.75) | Flow enter/exit |

---

## Appendix C — Deprecated Concepts

Do not implement in new code:

| Deprecated | Replacement |
|------------|-------------|
| XP / levels / points | Flow World growth |
| Focus Session (product copy) | Flow |
| Tab bar (Now/Stack/Pulse/Life) | Flow Canvas gestures |
| `AICoachView` chat threads | Flow briefing + coach moments |
| Coach tone setting | Behavior Memory |
| ADHD challenge setting | Behavior Memory |
| Insights bar charts | Memory Timeline |
| Task fly-off completion animation | Liquid collapse |
| Engagement notifications | Proactive orchestration (≤2/day) |
| Pin to lock screen setting | Auto-pin on Flow start |

---

## Appendix D — Document History

| Version | Date | Change |
|---------|------|--------|
| 1.0 | July 2026 | Unified Base + Craft + Attention OS specifications |

---

*End of canonical specification. Proceed to Phase D2 implementation plan upon approval.*
