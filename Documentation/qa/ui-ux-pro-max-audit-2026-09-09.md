# ui-ux-pro-max audit — 9 Sep 2026

Skill: `~/.cursor/skills/ui-ux-pro-max` (pro-rules + UX domain + SwiftUI stack).  
Screens reviewed: `screenshots/ux-agent/latest/*`.  
Keep Look After lime tokens — do **not** adopt skill teal/orange wholesale.

## Checklist findings → fixes

| Priority | Finding | Screen | Fix |
|----------|---------|--------|-----|
| A11y contrast | Dark `textMuted`/`textSecondary` too dim | All dark | Raised dark tokens |
| Truncation | Glance titles cut to “Brush tee…” | Briefing | 2-line title + layoutPriority |
| Overlay | Scroll hint sits on glance / near tab bar | Briefing | More bottom inset + stronger caption |
| Density / one job | Plan With Me duplicates Today chips + auto-expands | Today | Hide chips when negotiation active; skip auto-expand in UITests |
| Labels | Integrations → “Settings” redundant | You/Settings | Renamed “App settings” |
| Icon semantics | Factory Reset blue icon + red text | Settings | Destructive red icon+label |
| Disabled clarity | Capture Save unreadable when empty | Capture | Explicit “Type or speak to save” + clearer disabled tint |
| Contrast CTA | Decide for me text on lime | Brain | Force `accentOnPrimary` |
| Touch/contrast | Schedule check options used system blue `.bordered` | Today | Lime tinted capsules, 44pt min height |
| Capture consistency | Simulator dark appearance tinted “light” runs | Pipeline | Default UITest appearance = light |

## Still open (next pass)

- Bottom nav still 5 tabs + Capture FAB (skill prefers ≤5 total destinations).
- Morning review `12:00 AM – 10:30 PM` duration looks wrong (data/scheduler, not chrome).
- Larger Text / Dynamic Type sweep on dense timeline rows.
- Persist page overrides under `design-system/look-after/pages/` when redesigning Briefing/Today.
