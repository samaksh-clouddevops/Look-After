# iOS 26 App Store screenshot & preview shot list

**Document ID:** REL-IOS26-J1  
**Parent:** [ios26-revamp-plan.md](../qa/ios26-revamp-plan.md) Phase J1 · QA-12

Capture on a **physical iPhone on iOS 26** (simulator glass is not App Store truth). Prefer the current shipping device size App Store Connect requires for the primary set (e.g. 6.9" / 6.3" — confirm ASC current specs before upload).

Local scratch captures may live under the repo `screenshots/` folder; **do not** commit App Store Connect exports with PII.

---

## Required story order (conversion)

| # | Surface | Show | Avoid |
|---|---|---|---|
| 1 | **Briefing** first viewport | Brand calm, opaque cards, glass header actions, scroll hint | Dense glass wallpaper; unread system banners |
| 2 | **Today + NOW rail** | Clock rail, NOW/LATE chips, opaque row cards, glass All tasks / Replan | Every row as glass; fake translucent fills |
| 3 | **Capture** | Sheet zoomed from tab Capture; opaque composer field; glass Save / mic | Empty placeholder text that looks unfinished |
| 4 | **Tab bar + Capture** | Liquid Glass bar, center Capture, five tabs | Custom opaque bar that looks pre–iOS 26 |
| 5 | **Focus / ADHD** (optional slot) | High-contrast focus timer or emergency — **less** glass | Looping bounce / nauseating motion |
| 6 | **Widget / Island** (marketing crop OK) | Now widget + Focus Island with brand green `5A9E3F` | Adaptive colors that wash out on lock screen |

Light **and** dark if ASC localization needs both; at least one Reduce Transparency and one Reduce Motion frame for internal QA archive (not necessarily on the store page).

---

## Preview video (15–30s)

1. Open app → Briefing settle.  
2. Switch to Today → NOW visible.  
3. Tap Capture → morph/zoom → type or Speak → Save.  
4. Optional: Start Focus from Brain / Control Center.  
5. End on tab bar glass.

No sped-up looping springs. Prefer real Reduce Motion–safe pacing.

---

## Device / OS matrix (capture once per ship)

| Device | OS | Role |
|---|---|---|
| Shipping iPhone (16/17 class) | iOS 26 GM | Primary ASC set |
| Smaller iPhone if still supported | iOS 26 | Crowding check (Capture + tab bar) |
| iPhone with Dynamic Island | iOS 26 | Island marketing still |

---

## Sign-off

| Asset | Owner | Date | Done |
|---|---|---|---|
| Screenshot set uploaded to ASC | | | ☐ |
| Preview video uploaded (if used) | | | ☐ |
| Metadata matches binary UI | | | ☐ |
