# Look After — Full screenshot UI/UX audit (ui-ux-pro-max)

**Date:** 10 Sep 2026  
**Source:** `screenshots/ux-agent/latest/` (run `20260910-063102`)  
**Method:** Visual review of every capture + ui-ux-pro-max rule categories (a11y, touch, nav ≤5, contrast, forms, overlays)  
**Scope:** Analysis only — UI *and* UX. Keep Look After lime tokens (do not adopt skill teal/orange wholesale).

---

## Executive summary

This pass finds **many more issues than the original 9-point list**. Prior work fixed a few chrome items (Today icon toolbar, Briefing duplicate `+`, glance midnight range, floating scroll pill). **Core UX problems remain**: second dock (Replan), Capture-as-selected destination, first-viewport cognitive overload, trust/copy inconsistencies, and low-contrast secondary text.

| Severity | Approx count | Meaning |
|----------|--------------|---------|
| **P0** | ~14 | Blocks trust, obscures primary content, or breaks ADHD low-load goal |
| **P1** | ~28 | Consistency, hierarchy, a11y, scanability |
| **P2** | ~12 | Polish / next sweep |

### Cross-cutting themes (skill-aligned)

1. **Navigation overload** — Bottom destinations = 5 labeled tabs **+ Capture** (skill: bottom nav ≤5). Capture always reads “selected.”  
2. **Focus not obscured** — Sticky/floating chrome covers tasks (Today Replan, You routines).  
3. **Touch / hierarchy** — Multiple control families per screen; 10pt tab labels vs large titles.  
4. **Contrast** — Muted gray body/captions and disabled Capture CTA risk &lt;4.5:1.  
5. **ADHD cognitive load** — First viewport stacks greeting + hero + glance + nav + (Today) chips + week + banner + priorities + Replan.  
6. **Trust / data UX** — Priority order vs clock time; micro-start 2m vs task 5m; Dinner metadata format; Morning review at bottom of All Tasks.

---

## Per-screenshot findings

Severity: **P0** / **P1** / **P2** · Type: **UI** (look) · **UX** (behavior / mental model / load)

---

### S02 — Briefing (`S02_briefing.png`)

| ID | Sev | Type | Issue | Skill / rationale |
|----|-----|------|--------|-------------------|
| S02-01 | P0 | UX | First viewport: greeting (serif name dominates) + long hero copy + CTA + glance + tab bar — high cognitive load for ADHD | Progressive disclosure; one job per section |
| S02-02 | P0 | UX | Bottom nav = 6 destinations (5 + Capture); Capture solid lime reads permanently selected | Nav ≤5; selected-state clarity |
| S02-03 | P1 | UI | Icon-only customize + settings (no visible labels) | Icon-only needs AX labels (ok if AX only) — prefer clear differentiation |
| S02-04 | P1 | UX | Customize (sliders) vs Settings (gear) — similar chrome, unclear job split | One primary settings path |
| S02-05 | P1 | UX | Hero lists “Brush teeth (evening)” as a morning “main one” | Trust / relevance of briefing narrative |
| S02-06 | P1 | UI | Serif name vs sans everywhere else — Briefing feels like a different app | Type system consistency |
| S02-07 | P1 | UI | Glance pink dots vs hero green bullets — two status-color languages | Color not only / token discipline |
| S02-08 | P1 | UX | Glance cut by tab bar; no clear “what’s next” scroll cue in this frame | Overlay / sticky nav padding |
| S02-09 | P2 | UI | “FOR TODAY” lime on white — verify ≥3:1 for small caps | Contrast |

**What’s better vs older shots:** No floating “Scroll for more” pill; no duplicate header `+`; no `12:00 AM` Morning review in glance.

---

### S02-dark — Briefing dark (`S02-dark_briefing-dark.png`)

| ID | Sev | Type | Issue |
|----|-----|------|--------|
| S02D-01 | P1 | UI | Same structure/load as light; confirm muted secondary text ≥4.5:1 on dark cards |
| S02D-02 | P1 | UI | Pink glance dots on dark — meaning unclear |
| S02D-03 | P0 | UX | Same 6-destination nav + Capture selected-language |

---

### S04 — Tab bar (`S04_tab-bar.png`)

Same surface as Briefing first viewport; treat as **nav chrome audit**.

| ID | Sev | Type | Issue |
|----|-----|------|--------|
| S04-01 | P0 | UX | 5 labels + Capture = destination pressure |
| S04-02 | P0 | UI/UX | Capture circle dominates; competes with active Briefing tint |
| S04-03 | P1 | UI | Tab labels ~10pt — hard to read next to 18pt icons (text/button mismatch) |
| S04-04 | P1 | UI | Active = fill glyph + lime; Capture also lime → dual “selected” signals |
| S04-05 | P2 | UI | FAB slightly proud of bar — optical not flush |

---

### S05 — Today (`S05_today.png`) **worst remaining screen**

| ID | Sev | Type | Issue | Skill / rationale |
|----|-----|------|--------|-------------------|
| S05-01 | P0 | UX | **Replan bar is a second dock** covering Top Priorities / last row | Focus not obscured; sticky UI must not hide content |
| S05-02 | P0 | UX | First viewport: title + 3 icons + 2 chips + week strip + Micro-start (3 CTAs) + priorities + Replan + tab bar | Cognitive overload |
| S05-03 | P0 | UX | Micro-start offers 3 actions (“Start 2-min”, “Pick another”, “Not now”) *above* priorities — competing primaries | One primary per region |
| S05-04 | P0 | UX | Micro-start “2 minutes” vs list “5m” for same task — **trust break** | Consistent copy / data |
| S05-05 | P1 | UX | Priorities order: 9:00 AM above 8:00 AM — not chronological | Scan / mental model |
| S05-06 | P1 | UI | “Not now” chip clipped / cramped in 3-up row | Touch spacing; layout |
| S05-07 | P1 | UX | Context chips (“I just woke up” / “Going out”) use same glass language as toolbar — layer confusion | Component hierarchy |
| S05-08 | P1 | UX | Week strip + date + chips + banner before tasks — many horizontal systems | Density |
| S05-09 | P1 | UI | Icon toolbar OK now, but title ≫ controls optically | Text/control scale |
| S05-10 | P0 | UX | Capture still reads as selected primary in tab bar | Nav selected language |

---

### S14 — Task list (`S14_task-list.png`)

| ID | Sev | Type | Issue |
|----|-----|------|--------|
| S14-01 | P1 | UI | Header: close + title row, then 4 actions — better, but **primary + still optically larger** than peers |
| S14-02 | P1 | UX | Stack / import / add / menu — four chrome actions before filters (high load for “see my tasks”) |
| S14-03 | P1 | UI | Filter inactive text very light gray — contrast risk |
| S14-04 | P1 | UX | List order: Morning review after evening tasks — confusing vs time |
| S14-05 | P1 | UX | Dinner detail uses different metadata pattern (“Focus for 30 min…”) vs “Estimated time Xm” |
| S14-06 | P1 | UI | Row: checkbox + area icon + title + chevron — three affordances (dense) |
| S14-07 | P2 | UI | Import icon ambiguous without label |
| S14-08 | P2 | UI | Large vertical gap title → actions → filters |

---

### S19 — Brain (`S19_brain.png`)

| ID | Sev | Type | Issue |
|----|-----|------|--------|
| S19-01 | P1 | UX | Orb is visual hero but primary job is unclear vs “Decide for me” / “Ask Brain” / “tap orb” — **three start paths** |
| S19-02 | P1 | UI | Caption under buttons very light gray — contrast |
| S19-03 | P1 | UI | “Decide for me”: dark text on lime — verify contrast (prefer on-primary white if needed) |
| S19-04 | P1 | UX | Long analysis sentence under orb + two large CTAs — copy secondary, buttons dominate |
| S19-05 | P1 | UX | Orb + Decide + Capture FAB = three “hero circles” product-wide |
| S19-06 | P2 | UI | Large empty band above tab bar |
| S19-07 | P2 | UI | Ellipsis menu unlabeled visually |

**Note:** Orb depth improved vs early flat blob; state differentiation still weak in this still frame.

---

### S21 — Settings (`S21_settings.png`)

| ID | Sev | Type | Issue |
|----|-----|------|--------|
| S21-01 | P1 | UX | Sheet titled “Settings” with row “App settings” — redundant / confusing hierarchy |
| S21-02 | P1 | UI | Footer copy placement: Debug = *outside* card; Developer = *inside* card |
| S21-03 | P1 | UX | “Today” stats look like nav rows but aren’t tappable (no chevron) — false affordance |
| S21-04 | P1 | UX | Brain Inspector + Factory Reset in production Settings — high risk for ADHD users (destructive / debug noise) |
| S21-05 | P2 | UI | Large empty lower half |
| S21-06 | P2 | UI | Done as glass pill vs other chrome languages |

---

### S39 — Capture (`S39_capture.png`)

| ID | Sev | Type | Issue |
|----|-----|------|--------|
| S39-01 | P0 | UX | Disabled CTA “Type or speak to save” looks like a button but is inert — unclear affordance |
| S39-02 | P1 | UI | Disabled / placeholder / inactive chip text — low contrast |
| S39-03 | P1 | UX | Three selection languages: Speak outline, Auto filled, Save disabled capsule |
| S39-04 | P1 | UX | Close FAB at bottom center = same pattern as Capture `+` (cancel looks primary-adjacent) |
| S39-05 | P1 | UI | Huge empty region above dismiss — sparse / “broken” feel |
| S39-06 | P1 | UX | Category chips scroll off-screen (“Event” clipped) without peek affordance |
| S39-07 | P2 | UX | “View inbox” competes with Save as exit path |

---

### S42 — You (`S42_you.png`)

| ID | Sev | Type | Issue |
|----|-----|------|--------|
| S42-01 | P1 | UX | Routines card (“Breakfast”) cut by tab bar — same inset class as Today |
| S42-02 | P1 | UI | Progress bars thin vs large “You” title — weak hierarchy |
| S42-03 | P1 | UI | Motivational line + “Solid day ahead” muted — contrast risk |
| S42-04 | P1 | UX | Sun (appearance) + gear — two icon-only tools; sun meaning may be unclear |
| S42-05 | P2 | UX | Life areas only Inbox + Modules — sparse vs “You” as hub promise |
| S42-06 | P2 | UI | “See all insights →” link blue vs lime brand accent — third accent |

---

## ADHD-specific UX (product)

| ID | Sev | Issue |
|----|-----|--------|
| ADHD-01 | P0 | Too many competing CTAs before the user can *start one thing* (Today Micro-start ×3 + Replan + Capture + priorities) |
| ADHD-02 | P0 | Second dock (Replan) teaches “two bottoms” — increases decision friction |
| ADHD-03 | P1 | Conversational briefing is long; main actions buried under prose |
| ADHD-04 | P1 | Inconsistent time/priority ordering erodes trust (“is the plan real?”) |
| ADHD-05 | P1 | Debug/destructive tools adjacent to everyday Settings |

---

## Recommended fix order (UI + UX)

Do **structure first**, chrome second — so screenshots change obviously.

### Wave A — UX structure (P0)

1. **Kill Replan-as-second-dock** — Move “Plan with me” into Today toolbar / section action; no full-width floating bar over content.  
2. **Capture selected language** — Outline + muted plate always; never share active-tab lime fill. Consider Capture outside the 5-tab count (sheet-only).  
3. **Today first viewport** — One primary: either Micro-start *or* Top Priorities; collapse chips/week under progressive disclosure.  
4. **Trust copy** — Align micro-start duration with task estimate; chronologically sort priorities; briefing “main ones” = morning-relevant only.

### Wave B — Consistency / a11y (P1)

5. Control matrix enforcement (toolbar / chip / CTA / tab / FAB).  
6. Contrast pass on muted captions + Capture disabled.  
7. Settings: rename hierarchy; hide Debug/Developer behind unlock; unify footers.  
8. Capture: clearer disabled vs primary; quieter dismiss; chip overflow cue.  
9. Brain: one primary start path; stronger orb state; fix caption contrast.

### Wave C — Polish (P2)

10. Type: serif only for intentional brand moments with a rule.  
11. Dynamic Type / XXXL sweep.  
12. Reduced-motion screenshot verification.

---

## Explicitly out of scope this doc

- Implementing Wave A–C (await “go”)  
- Adopting skill teal/orange palette  
- Backend scheduling correctness beyond user-visible trust

---

## Screenshot index

| File | Screen |
|------|--------|
| `S02_briefing.png` | Briefing light |
| `S02-dark_briefing-dark.png` | Briefing dark |
| `S04_tab-bar.png` | Tab bar / Briefing chrome |
| `S05_today.png` | Today |
| `S14_task-list.png` | All Tasks |
| `S19_brain.png` | Executive Brain |
| `S21_settings.png` | Settings sheet |
| `S39_capture.png` | Capture sheet |
| `S42_you.png` | You |

---

*Skill sources: ui-ux-pro-max quick-reference (a11y, touch 44pt, nav ≤5, contrast 4.5:1, forms/disabled, focus-not-obscured) + per-frame visual review. Keep DesignSystem lime.*
