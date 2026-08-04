# Look After — Widget System V2
**Executive Brain Widget Ecosystem · Design System V4 · WidgetKit**

**Branch:** `feature/widget`  
**Status:** Spec + foundation  
**Visual source of truth:** `LookAfterTheme` / Design System V4

---

## 1. Philosophy

Widgets are **not miniature dashboards**.

| Rule | Meaning |
|------|---------|
| One widget · one purpose · one glance | Answer a single question in ≤1s |
| Extension of the Executive Brain | Surface deterministic recommendations, never invent data |
| Saves an app open | If it doesn’t reduce friction, it doesn’t ship |
| Apple-quality calm | Journal-like cards, breathable whitespace, no neon |
| Semantic color only | No hardcoded ramps; accent green only for *action* |

**North-star glance question:** *What matters right now?*

---

## 2. Design language (V4)

### Surfaces
| Token | Light | Dark |
|-------|-------|------|
| Canvas | `#F8F8F6` | `#111315` |
| Card / primary surface | `#FFFFFF` | `#191C1F` |
| Elevated | `#ECEEF1` | `#2B3036` |
| Border | `#E5E7EB` | `#31353A` |

### Accent
- **Action green** `#C8FF4D` — current action, selection, progress, complete, recording only  
- **Never** full-card green backgrounds  
- On-accent text: `#1C1C1E`

### Semantic accents (icons / chips / progress only)
| Domain | Color | Hex |
|--------|-------|-----|
| Health | Sage | `#74C69D` |
| Focus | Blue | `#7DD3FC` |
| Reflection | Lavender | `#B8A1FF` |
| Learning | Amber | `#F4C95D` |
| Finance | Gold | `#E9C46A` |
| Relationships | Rose | `#F497B6` |
| Travel | Teal | `#4DD0E1` |
| Warning | Orange | `#F6C453` |
| Error | Red | `#F87171` |

### Typography (widget scale)
- Eyebrow / section: `dsCaption` · semibold · secondary  
- Primary line: `dsHeadline` / `dsBody` · primary · max 2 lines  
- Meta: `dsMetadata` · muted  
- Countdown: monospaced digit · accent sparingly  

### Spacing / radius
- Widget padding: 14–16  
- Internal gap: 8–12  
- Card radius in-app: 24; widget chrome uses system continuous corners  
- Min touch: 44pt for interactive controls  

### Motion
- Subtle only; honor Reduce Motion  
- No looping decorations on Home Screen  
- Live Activities: system countdown text, not custom timers spinning forever  

---

## 3. Audit — current (V1)

| Asset | Families | Purpose | Verdict |
|-------|----------|---------|---------|
| **NowWidget** | S, M | Top task + energy | **Keep → evolve to Executive Recommendation** |
| **EnergyWidget** | S, accessory rect/inline | Energy + sleep/steps/HRV | **Keep → evolve to Health + Life State split** |
| **TasksWidget** | M, L | Top 3 tasks | **Keep → evolve to Today (timeline, not list dump)** |
| **FocusLiveActivity** | LA + Island | Focus countdown | **Keep · polish** |
| **NowPinLiveActivity** | LA + Island | Pinned now | **Keep · map to Recommendation pin** |

### Gaps
- No medication / calendar / capture / habits / weekly / brain / memory widgets  
- No App Intents / interactive buttons  
- No deep links  
- No Smart Stack relevance  
- Large Tasks underused (same 3 rows)  
- Energy accessories lack dedicated layouts  
- Duplicate `WidgetDataStore` load path  
- Accent mismatch: `DesignSystem.accentPrimary` was forest green vs theme `#C8FF4D`  
- Single timeline entry, 15 min — stale without app open  

### Remove / avoid
- Generic multi-metric “dashboard” layouts  
- Task lists longer than glance allows  
- Medical *advice* copy (status only)  

---

## 4. Widget catalog V2

### Priority P0 (ship first)
| # | Widget | Question | Families | Interactive |
|---|--------|----------|----------|-------------|
| 1 | **Executive Recommendation** | What now? | S, M, L, StandBy-friendly M | Complete · Open · Snooze |
| 2 | **Today** | What’s next on my day? | M, L | Open timeline |
| 3 | **Focus** | Am I in deep work? | S, M + LA/Island | Start · End |
| 4 | **Health** | How’s recovery? | S, accessory* | Open health |
| 5 | **Capture** | Capture a thought | S, M | Voice · Text · Task |

### Priority P1
| # | Widget | Question | Families |
|---|--------|----------|----------|
| 6 | Medication | What’s due? | S, M, accessory circular |
| 7 | Calendar | Next meeting? | S, M |
| 8 | Habits | Routines today? | M |
| 9 | Life State | Energy · attention · recovery | S, circular, rect |
| 10 | Brain | Brain status / open Ask | S, M |

### Priority P2
| # | Widget | Notes |
|---|--------|-------|
| 11 | Weekly Review | Fri/Sun relevance only |
| 12 | Memory | Single insight chip |
| — | Control widgets | Focus start, capture, water |
| — | Watch complications | Future |

### Live Activities / Island (active only)
Focus · Meeting countdown · Medication window · Travel · Workout · Cooking · Routine  
**Never** static “info” Live Activities.

---

## 5. Per-widget content model

### 5.1 Executive Recommendation
| Size | Content |
|------|---------|
| **S** | Eyebrow NOW · title (2 lines) · optional ~min |
| **M** | Title · one *why* line · energy chip · primary action |
| **L** | Title · why · next step · Complete / Snooze / Open |

Empty: “You’re clear” + soft capture CTA.

### 5.2 Today
| Size | Content |
|------|---------|
| **M** | Next event · next task · free-block minutes |
| **L** | Thin timeline (≤4 rows) · capacity band |

No full calendar dump.

### 5.3 Focus
| Size | Content |
|------|---------|
| **S** | Icon + remaining or “Start focus” |
| **M** | Task · countdown · End |

### 5.4 Health
Sleep hours · energy % · recovery label. Optional single secondary (HRV *or* steps—not both unless M+).

### 5.5 Capture
One large control. Variants: Voice / Note / Task. Opens app deep link in &lt;300ms path.

### 5.6 Medication
Name · time · Taken / Due. **No** dosage advice, interactions, or LLM text.

---

## 6. Architecture

```
Main App
  ContextOrchestrator + BrainVM + Tasks + Meds + Health
           │
           ▼
  WidgetSnapshotBuilder (Core, pure)
           │
           ▼
  WidgetDataStore (Data) → App Group UserDefaults
           │
           ▼
  WidgetCenter.reloadTimelines(ofKind:)
           │
LookAfterWidget Extension (Core only)
  TimelineProvider → ExecutiveWidgetEntry
  Views + shared WidgetChrome
  AppIntents (complete, snooze, water, start focus) → App Group commands
           │
           ▼
  Main app processes intent queue on foreground / BG
```

### Rules
1. Extension depends on **LookAfterCore only**  
2. One **canonical** `WidgetDataStore` API in Core or Data; extension uses the same types  
3. Snapshots are **pre-rendered strings/metrics** — no brain ticks in the extension  
4. Reloads are **kind-scoped**, not always `reloadAllTimelines()`  
5. Intents write to App Group command queue; main app is source of truth  

### Deep links
```
lookafter://recommend
lookafter://today
lookafter://focus
lookafter://capture?mode=voice|text|task
lookafter://medication
lookafter://health
lookafter://brain
lookafter://task/{id}
```

---

## 7. Timeline strategy

| Kind | Entries | Policy | Relevance |
|------|---------|--------|-----------|
| Recommendation | 1 current + optional next slot | `.after` 15–30m or app push | Morning high; deep night low |
| Today | Multi-entry at event boundaries | `.atEnd` of entry stack | Work hours |
| Focus | Driven by Live Activity when active; static otherwise | On session change | Active session → max |
| Health | 1 entry | After health sync / 30–60m | Morning post-wake |
| Capture | Static | Rare reload | Always mild |
| Medication | Entries at dose times | `.atEnd` | Around due ±30m |
| Weekly | Fri PM / Sun | Date-gated | Zero other days |

**Avoid** aggressive reload spam. Prefer app-driven `reloadTimelines(ofKind:)` after brain refresh / task complete / health sync.

---

## 8. Smart Stack

Expose `TimelineEntry` relevance where supported (iOS version permitting):

| Context | Prefer |
|---------|--------|
| Morning | Recommendation · Health · Today |
| Pre-meeting | Calendar · Focus prep |
| Midday | Hydration (habit) · Capture |
| Evening | Habits · Reflection/Brain |
| Night | Weekly (weekend) · dim relevance |

---

## 9. Interactive flows

| Intent | Effect | Opens app? |
|--------|--------|------------|
| Complete recommendation | Queue complete task id | No if offline queue ok |
| Snooze 1h | Queue defer | No |
| Start focus | Start session / open focus | Prefer in-app if complex |
| End focus | End LA + session | No |
| Mark med taken | MedicationStore via queue | No |
| Log water | Hydration +250ml | No |
| Capture | Always deep link | Yes (input UX) |

Show confirmation via widget state flip on next timeline (optimistic local snapshot patch optional P1).

---

## 10. Accessibility

- VoiceOver labels: full sentence (“Next step: Review notes, about 25 minutes”)  
- Dynamic Type: prefer system text styles where possible; avoid fixed micro type below 11pt  
- Reduce Motion: no decorative rings animation  
- High contrast: border ≥1pt; don’t rely on green alone for “taken” (use checkmark symbol)  
- Color blindness: pair color chips with icons  

---

## 11. Migration plan

| Phase | Work | Exit |
|-------|------|------|
| **A** | Spec + accent fix + `WidgetSnapshotV2` models + chrome components | Types compile |
| **B** | Rebuild P0 widgets (Recommendation, Today, Focus, Health, Capture) | Gallery matches mock structure |
| **C** | AppIntents + deep links + sync builder | Interactive paths work |
| **D** | Medication, Calendar, Habits, Life State, Brain | P1 complete |
| **E** | Smart Stack relevance, Weekly, Memory, Controls | P2 |
| **F** | Remove V1 kinds after one release overlap | No `NowWidget`/`EnergyWidget`/`TasksWidget` names |

**Overlap:** Ship V2 kinds with new `kind` strings; keep V1 one release for existing home screens.

---

## 12. Performance budgets

| Metric | Target | Hard fail |
|--------|--------|-----------|
| Timeline `getTimeline` | &lt; 50ms | &gt; 200ms |
| Snapshot encode (main) | &lt; 20ms | &gt; 100ms |
| Intent handle | &lt; 100ms | &gt; 500ms |
| Focus LA start (deferred) | UI first, LA ≤250ms later | Blocks UI |

---

## 13. Success criteria

- Glance answers “what matters now?” without opening app  
- Feels first-party Apple + Look After identity  
- Zero medical advice from widgets  
- V4 light/dark parity  
- Every shipped widget has empty + loading + error/placeholder  

---

## 14. Deliverable index

| # | Deliverable | Location |
|---|-------------|----------|
| 1 | Design specification | This document |
| 2 | Architecture | §6 |
| 3 | Widget gallery | §4–5 + SwiftUI Previews |
| 4–5 | Light/Dark | V4 tokens + previews |
| 6 | Timeline strategy | §7 |
| 7 | Interactive flows | §9 |
| 8 | Smart Stack | §8 |
| 9 | Accessibility | §10 |
| 10 | Migration | §11 |

---

## 15. Placeholder · loading · error

| State | UI |
|-------|-----|
| **Placeholder** | Soft sample copy; never real PII in gallery |
| **Empty** | One calm line + optional single action |
| **Stale** (`updatedAt` > 6h) | Muted “Open Look After to refresh” |
| **Error** | Don’t show stack traces; fall back to last good snapshot |

---

## 16. Gallery (content wireframes)

### Recommendation · Small
```
┌──────────────────┐
│ NOW          72% │
│ Review notes     │
│ ~25 min          │
└──────────────────┘
```

### Recommendation · Medium
```
┌────────────────────────────────────┐
│ NOW · High energy                  │
│ Review project notes               │
│ Open window before 11am standup    │
│              [ Complete ]  [ ··· ] │
└────────────────────────────────────┘
```

### Today · Medium
```
┌────────────────────────────────────┐
│ TODAY                              │
│ 10:30  Standup · 15m               │
│ Next   Review notes · 25m          │
│ Free   48 minutes                  │
└────────────────────────────────────┘
```

### Health · Small
```
┌──────────────────┐
│ ENERGY           │
│ 72%              │
│ 7.2h sleep       │
│ Recovery good    │
└──────────────────┘
```

### Capture · Small
```
┌──────────────────┐
│                  │
│    (  mic  )     │
│    Capture       │
│                  │
└──────────────────┘
```

Light: warm canvas + white cards. Dark: charcoal canvas + elevated cards. Accent only on Complete / progress / recording.
