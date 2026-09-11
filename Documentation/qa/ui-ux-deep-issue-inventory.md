# Look After — UI/UX deep issue inventory

**Date:** 9 Sep 2026  
**Sources:** `screenshots/ux-agent/latest/*`, ui-ux-pro-max pro-rules + UX domains, component code review  
**Mode:** Analysis only (no fixes in this document)

---

## What we check (audit framework)

This is the checklist used for Look After reviews. Your 9 points map into these categories.

### A. Accessibility & contrast (CRITICAL)
- Body/caption text ≥ 4.5:1 on light and dark surfaces  
- Icon/control boundaries ≥ 3:1 when they carry meaning  
- Disabled states readable but clearly non-interactive  
- Color never the only status signal  

### B. Touch & interaction (CRITICAL)
- Hit targets ≥ 44×44 pt (iOS)  
- ≥ 8 pt gap between adjacent controls  
- One primary gesture per region (no overlapping hit areas)  
- Clear pressed / selected / disabled feedback  

### C. Layout, safe area & density (HIGH)
- Headers / tab bars / CTAs respect safe areas  
- Scroll content not hidden behind fixed chrome  
- Fixed chrome docks to edges (not floating mid-safe-area)  
- 4/8 pt spacing rhythm; section hierarchy clear  

### D. Component & style consistency (HIGH)
- One control family per hierarchy level (size, shape, glass vs filled vs plain)  
- Icon size/stroke/filled-vs-outline discipline  
- Button corner radius and height shared within a screen family  
- No emoji used as structural icons  

### E. Typography & hierarchy (MEDIUM–HIGH)
- Tokenized type scale (screen title / body / caption / tab)  
- Serif reserved for intentional brand moments only  
- Text size compatible with neighboring control size  
- No orphaned wraps, mid-word truncation of important titles  

### F. Navigation patterns (HIGH)
- Bottom destinations ≤ 5 (skill default); Capture FAB counted as destination pressure  
- Selected vs unselected states consistent across tabs  
- FAB does not steal visual weight from the active tab ambiguously  

### G. Forms & sheets (MEDIUM)
- Labels, hints, disabled clarity  
- Sheet vs page chrome not fighting for attention  
- One job per section  

### H. Motion & polish (MEDIUM)
- Shared motion tokens; reduced-motion respected  
- Hero visuals feel intentional (not default/gradient filler)  

### I. Product / ADHD-specific UX
- Low cognitive load: few competing CTAs in first viewport  
- Overlays (scroll hint, assistant, banners) must not obscure primary actions  
- Copy must stay scannable (no truncated critical labels)

---

## Confirmed issues (mapped to your list + extras)

Severity: **P0** blocks trust/use · **P1** clear polish/consistency · **P2** nice-to-fix / next pass

### 1. Button sizes and shapes — **P0/P1**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| B-01 | Multiple button “families” coexist without a rule: glass circle icon, glass capsule+label, glassProminent filled, plain bordered, lime capsule chips | Today header, Task list header, Capture, Schedule check, Brain | Today: `All tasks` capsule + icon circles; Task list: 4 different header control treatments; Capture Save vs Speak vs chips |
| B-02 | Corner radii inconsistent (circle FAB vs continuous rounded CTAs vs chip capsules vs card radius) | Global | Visual mismatch between Capture FAB (circle), Continue CTA (pill), Schedule options (capsule), Settings Done (glass pill) |
| B-03 | Vertical padding / minHeight mixed: some use `minTouchTarget` (44), some use ad-hoc `padding(.vertical, 14)`, some caption-sized chips feel shorter than neighbors | Capture, Schedule check, Plan With Me | Schedule check three options cramped in one row; Capture Speak smaller than Save |
| B-04 | Icon glyph sizes float (16 / 18 / 20 / 22) inside supposedly equal 44pt frames | Task list header, Today header | Task list `plus.circle.fill` at 22 vs others at 18–20 |

### 2. Overlapping buttons / hit areas — **P0**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| O-01 | Bottom Capture FAB visually overlaps tab-bar top edge and crowds Review/Brain slots | Bottom nav all tabs | 6 slots in one `HStack`; FAB taller than tab labels |
| O-02 | Scroll-for-more pill still competes with glance rows / near tab bar | Briefing | Overlay sits on “Today at a Glance” content |
| O-03 | Plan With Me collapsed chip + tab bar + content stack — bottom of Top Priorities clipped | Today | Last priority row cut by “Replan or adjust my day” |
| O-04 | Task list header: four glass controls packed against large title — optical overlap / crowding even when hit areas are 44pt | All Tasks | Title + stack + import + add + menu |
| O-05 | Briefing top: three circular actions next to greeting compete with Capture FAB for “add” mental model | Briefing | Header `+` and bottom Capture both mean “add” |

### 3. Font inconsistencies — **P1**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| T-01 | Serif used for user name on Briefing; almost everything else is sans — intentional brand moment, but **Tomorrow/other titles don’t share the same system**, so Briefing feels like a different app | Briefing vs Today/You/Brain | `ds…UserName` serif vs `textStyleScreenTitle` sans |
| T-02 | Raw `.system(size: 10/13/14/16…)` mixed with `dsCaption` / `dsBody` / `dsLargeTitle` | Tab labels, Task list, Settings | Tab titles hard-coded 10pt; Task list completed banner uses raw 13pt |
| T-03 | Weight/tracking inconsistent for same hierarchy (semibold caption vs medium caption vs bold SF Symbol) | Headers | Glass icon buttons use different symbol weights |
| T-04 | Truncation hierarchy wrong: important titles/metadata ellipsize while chrome stays large | Today Top Priorities, glance (partially fixed) | “Health & Recov…”, “20…”, “M…” |

### 4. Inconsistent bottom-menu button styles — **P0**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| N-01 | Tabs = icon+10pt label+plain; Capture = filled lime circle, no label | Bottom nav | Two different control paradigms in one bar |
| N-02 | Selected tab = lime tint + filled glyph; Capture always lime filled → Capture always looks “selected” | Bottom nav | Competes with active tab color language |
| N-03 | 5 labeled destinations + Capture = 6 destinations (skill prefers ≤5) | Bottom nav | Cognitive + layout pressure |
| N-04 | Tab icon size 18 / Capture glyph 18 but Capture circle 44 dominates optical weight | Bottom nav | Asymmetric visual hierarchy |

### 5. Bottom menu placement (too high / not docked) — **P0**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| N-05 | Tab bar still reads slightly “floating” above home indicator vs edge-docked iOS HIG chrome | All main tabs | Plate uses `ignoresSafeArea` but padding/top chrome may leave a perceived gap |
| N-06 | Content bottom inset vs assistant chip vs tab bar stacking creates a “second dock” | Today | “Replan or adjust my day” sits above tab bar like a second nav |
| N-07 | Capture dismiss FAB (X) sits in home-indicator zone similarly to Capture + — two center-bottom circles across flows | Capture sheet | Pattern collision with tab Capture |

### 6. Today top bar asymmetrical / out of place — **P0**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| H-01 | Header mixes **labeled capsule** (`All tasks`) with **icon-only glass circles** (refresh, settings) | Today | Asymmetric cluster; not a balanced trailing toolbar |
| H-02 | Trailing controls don’t share equal optical width; `All tasks` steals weight from title | Today | Large title left, uneven trailing |
| H-03 | Quick chips (“I just woke up” / “Going out”) sit under header with similar glass language as toolbar — unclear which layer is primary | Today | Header vs context chips blur |
| H-04 | Week strip + date line + chips + schedule banner = too many horizontal systems before timeline | Today first viewport | ADHD cognitive load |

### 7. Task list buttons overlapping / not sized / not shared — **P0**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| L-01 | Four trailing header buttons: glass / glass / glassProminent / glass — inconsistent elevation | All Tasks | Add is prominent; others glass; import tinted accent |
| L-02 | Icon sizes 18 / 18 / 22 / 20 inside same frame — looks unaligned | All Tasks | `plus.circle.fill` larger |
| L-03 | Filter chips (All/Today/…) height and selected fill don’t match header control language | All Tasks | Second control system |
| L-04 | Title vs trailing control cluster still fights for horizontal space (wrap risk under Dynamic Type) | All Tasks | Previously saw “All / Task / s”; mitigated but fragile |
| L-05 | Row chevrons + checkboxes + category icons = three left/right affordances; dense for ADHD | Task rows | Crowded cards |

### 8. Text and button sizes not compatible — **P1**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| C-01 | Screen titles (`dsLargeTitle` / screen title) much larger than adjacent 44pt controls → controls feel like footnotes | Today, Tasks, You, Brain | Optical imbalance |
| C-02 | Schedule check options: caption-sized text in short capsules next to body copy — undersized vs message | Today | Three options cramped |
| C-03 | Capture disabled CTA text (“Type or speak to save”) may still undershoot contrast on light gray | Capture | Disabled clarity vs readability tradeoff |
| C-04 | Tab labels at 10pt are below comfortable reading size next to 18pt icons | Bottom nav | Text/button incompatibility |
| C-05 | Brain body copy + two large CTAs: copy feels secondary but wraps long; buttons dominate | Brain | Hierarchy imbalance |

### 9. Brain AI circle looks basic — **P1**

| ID | Issue | Where | Evidence |
|----|--------|--------|----------|
| R-01 | Orb is a soft radial gradient blob (~220pt) without depth layers, rim, specular, or idle motion presence | Brain | Reads as generic “AI glow” filler |
| R-02 | Orb state (ready/listening/thinking/speaking) under-differentiated visually in screenshots | Brain | Status mostly via caption text |
| R-03 | Orb competes with lime Decide CTA and Capture FAB — three “hero” circles in the product | Brain + nav | Visual noise |
| R-04 | Instruction copy under orb uses em-dash; low hierarchy vs buttons | Brain | Polish |

---

## Additional issues (beyond your 9)

### Briefing
| ID | Issue | Sev |
|----|--------|-----|
| BR-01 | Duplicate “add” affordances (header + and Capture FAB) | P1 |
| BR-02 | Scroll hint still content-competitive | P1 |
| BR-03 | Morning review range `12:00 AM – 10:30 PM` looks broken (data/UX trust) | P0 |
| BR-04 | Three header icon buttons without visible labels (rely on AX only) | P2 |
| BR-05 | First viewport density: hero card + glance + hint + tab bar | P1 |

### Capture
| ID | Issue | Sev |
|----|--------|-----|
| CA-01 | Speak (outline) vs Auto chip (filled) vs Save (prominent) — three selected-language systems | P1 |
| CA-02 | Large empty vertical gap above dismiss FAB | P2 |
| CA-03 | Close FAB color identical to Capture/Decide — cancel looks primary | P1 |

### You / Settings
| ID | Issue | Sev |
|----|--------|-----|
| Y-01 | Progress bars thin vs large “You” title | P2 |
| Y-02 | Settings sheet: footer/description placement inconsistent (Debug vs Developer) | P2 |
| Y-03 | Integrations row still lives under a Settings sheet titled Settings (mild redundancy even after “App settings”) | P2 |

### Cross-cutting
| ID | Issue | Sev |
|----|--------|-----|
| X-01 | Glass / glassProminent / plain / bordered / custom capsule — no documented control matrix | P0 |
| X-02 | No single “toolbar icon button” component shared by Briefing / Today / Tasks / You | P0 |
| X-03 | Dark mode tokens improved but light secondary grays still risk <4.5:1 on white | P1 |
| X-04 | Dynamic Type / XXXL not validated in this capture set | P1 |
| X-05 | Reduced-motion path not screenshot-verified this pass | P2 |

---

## Severity summary

| Severity | Count (approx) | Meaning |
|----------|----------------|---------|
| **P0** | ~12 | Fix before calling UI “shippable polish” |
| **P1** | ~20 | Clear consistency / ADHD cognitive-load wins |
| **P2** | ~8 | Next sweep / niceties |

### Highest-leverage fix themes (for when you say go)
1. **Control matrix** — one ToolbarIconButton, one PrimaryCTA, one Chip, one TabItem, one FAB language  
2. **Bottom nav redesign** — dock flush, unify Capture vs tabs, reduce destination pressure  
3. **Today header** — equal icon toolbar OR one primary text button, not mixed  
4. **Task list header** — shared sizes, one prominent action max  
5. **Brain orb** — designed states (rim, pulse, listening ring), not flat gradient  
6. **Type scale enforcement** — ban raw `.system(size:)` outside tokens for UI chrome  

---

## Explicitly out of scope of this list
- Backend / scheduling correctness beyond user-visible trust (except BR-03 as UX trust)  
- StoreKit / auth flows  
- macOS parity  

---

*Next step when you approve: turn P0 cluster into an ordered implementation plan, then fix screen-by-screen with re-capture.*
