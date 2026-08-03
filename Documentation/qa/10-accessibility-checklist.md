# 10. Accessibility Checklist

**Document ID:** QA-10  
**Parent:** [README.md](README.md)

Accessibility validation per [ATTENTION_OS_SPEC.md](../ATTENTION_OS_SPEC.md) §22 and Apple HIG.

**Primary settings to test:** VoiceOver, Dynamic Type (including XXXL), Reduce Motion, Increase Contrast, Bold Text.

---

## Global Requirements

| Requirement | Standard | Verification |
|-------------|----------|--------------|
| Touch targets | ≥ 44×44 pt | Measure ADHDFloatingDock, bottom nav, task actions |
| Color contrast | WCAG AA (4.5:1 body, 3:1 large) | Accessibility Inspector |
| Focus order | Logical top-to-bottom, left-to-right | VoiceOver swipe order |
| Dynamic Type | Layout adapts to XXXL | No clipped hero titles |
| Reduce Motion | No essential info in motion only | Mode switch, focus timer |
| Labels | Every interactive control labeled | VoiceOver rotor |
| Haptics | Not sole feedback channel | Visual + text duplicate |

---

## VoiceOver Checklist

| Screen | Element | Required label/hint | Pass |
|--------|---------|---------------------|------|
| S04 Bottom nav | Each tab | Tab name + selected state | ☐ |
| S05 TodayView | Hero CTA | Task title + why + "Starts task" | ☐ |
| S05 TodayView | Capacity card | Band name + brief reason | ☐ |
| S14 TaskListView | Task row | Title, priority, due, actions | ☐ |
| S14 TaskListView | Swipe actions | "Complete", "Defer" announced | ☐ |
| S25 OnboardingView | Progress | "Step X of Y" | ☐ |
| S25 OnboardingView | All inputs | Field purpose | ☐ |
| S29 Modules grid | Each tile | Module name + badge | ☐ |
| S30 Emergency | Exit | "Exit emergency mode" | ☐ |
| S31 Focus | Timer | Remaining time updates | ☐ |
| S35 Cycle | Phase card | Phase + day + countdown | ☐ |
| S43 Widget | Hero | Accessible via widget (system) | ☐ |

---

## Dynamic Type Checklist

Test at **Large**, **XXL**, and **XXXL** (Settings → Accessibility → Display & Text Size).

| Screen | Element | Pass criteria | Pass |
|--------|---------|---------------|------|
| S05 TodayView | Hero title | Wraps or truncates gracefully | ☐ |
| S05 TodayView | Why-now line | Fully readable | ☐ |
| S14 TaskListView | Row text | No overlap with badges | ☐ |
| S25 OnboardingView | Step title | No clip at 28pt bold | ☐ |
| S21 SettingsView | Section headers | Visible | ☐ |
| S08 Capacity card | Band label | No truncation of band name | ☐ |
| S09 Planning chat | Bubbles | Scrollable; text wraps | ☐ |

---

## Reduce Motion Checklist

| Interaction | Full motion | Reduce Motion expected | Pass |
|-------------|-------------|------------------------|------|
| Experience mode switch | Scale + opacity | Opacity fade primarily | ☐ |
| Tab selection | Icon swap | Instant or subtle fade | ☐ |
| Focus timer | Pulsing ring | Static or minimal | ☐ |
| Progress bars | Animated fill | Instant or reduced | ☐ |
| Toast appear | Slide | Fade | ☐ |
| Card stack swipe | Physics | Functional without bounce | ☐ |

---

## High Contrast / Bold Text

| Check | Pass |
|-------|------|
| `DesignSystem.textMuted` readable on `PremiumBackground` | ☐ |
| `DesignSystem.accentPrimary` buttons visible | ☐ |
| Bold Text does not break single-line toolbars | ☐ |

---

## Keyboard & Switch Control (iPad / external keyboard)

| Check | Pass |
|-------|------|
| Tab through onboarding fields | ☐ |
| Settings form navigable | ☐ |
| Task list focusable rows (if applicable) | ☐ |

---

## Per-Screen Accessibility Test Cases

### LO-IOS-A11Y-001 — Bottom nav selected trait

| Priority | P0 |
| Steps | Enable VoiceOver → select each tab |
| Expected | `.isSelected` on active tab; name announced |

### LO-IOS-A11Y-002 — Hero button hint

| Priority | P0 |
| Expected | Hint describes action outcome |

### LO-IOS-A11Y-003 — Task row complete action

| Priority | P0 |
| Expected | Swipe action labeled |

### LO-IOS-A11Y-004 — Emergency mode escape

| Priority | P0 |
| Expected | Clear exit control always reachable |

### LO-IOS-A11Y-005 — Dynamic Type XXXL hero

| Priority | P0 |
| Expected | No layout break on TodayView |

### LO-IOS-A11Y-010 — Contrast muted text

| Priority | P1 |
| Tool | Accessibility Inspector contrast audit |

### LO-IOS-A11Y-020 — Reduce Motion mode switch

| Priority | P1 |
| Expected | No disorienting scale animation |

### LO-IOS-A11Y-030 — Onboarding progress announced

| Priority | P1 |

### LO-IOS-A11Y-040 — Cycle dashboard phase readable

| Priority | P1 |
| Gating | Female profile only |

### LO-IOS-A11Y-050 — Voice capture without sight

| Priority | P2 |
| Expected | Audio feedback on record start/stop |

---

## ADHD-Specific Accessibility

LifeOS targets ADHD users — additional UX-a11y overlap:

| Principle | Validation |
|-----------|------------|
| Cognitive load | 3-second test on P0 screens ([04-screen-test-cases.md](04-screen-test-cases.md)) |
| Shame-free copy | Coach/emergency strings never blame user |
| Clear next action | Single primary CTA per screen where possible |
| Overwhelm mode | Emergency reduces choices (S30) |

---

## Widget & Live Activity Accessibility

| Surface | Requirement | Pass |
|---------|-------------|------|
| Now widget | System widget a11y | ☐ |
| Energy widget | Band text legible at default size | ☐ |
| Live Activity | Timer readable on Lock Screen | ☐ |
| Dynamic Island | Compact/expanded readable | ☐ |

---

## Accessibility Release Gate

Before release:

- [ ] All LO-IOS-A11Y P0 cases pass on physical device  
- [ ] VoiceOver walkthrough of FLOW-001 and FLOW-002 complete  
- [ ] Dynamic Type XXXL on S05, S14, S25 pass  
- [ ] Reduce Motion verified on mode switch and focus  
- [ ] No S1/S2 accessibility defects open  

---

## Defect Severity for Accessibility

| Severity | Example |
|----------|---------|
| S1 | Hero unreachable with VoiceOver |
| S2 | Task complete impossible with Switch Control |
| S3 | Misordered focus on non-critical screen |
| S4 | Suboptimal hint text |
