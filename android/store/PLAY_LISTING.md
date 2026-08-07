# Look After — Google Play listing draft

## App name
Look After

## Short description (80 chars)
Calm ADHD-aware execution: Today board, coach, meds, focus body double.

## Full description
Look After is a calm executive layer for noisy days.

**Today** — one intentional board. Capture thoughts, schedule deep work, complete with a tap.

**Brain** — offline coach plus optional cloud LLM planning. Strip overload, spread work across days, protect anchored commitments.

**Focus** — timed ADHD sessions with ambient body double, optional front-camera mirror, and Do Not Disturb when permitted.

**Care** — medication inventory on the unified LifeEngine, Health Connect readiness when available.

**Insights** — seven-day completion, focus minutes, streaks, and gentle coaching lines.

Privacy-first and local by default. Optional Firebase Auth / sync when you add your own `google-services.json`. Optional OpenAI-compatible coach via `LOOKAFTER_LLM_API_KEY`.

## Category
Productivity

## Content rating
Everyone

## Tags
ADHD, productivity, focus, habits, health, calendar, planner

## Privacy policy URL
https://samaksh-clouddevops.github.io/Look-After/privacy
(or host `android/store/privacy-policy.html`)

## Support email
support@lookafter.app

## Screenshots (capture order)
1. Today timeline with hero card
2. Brain coach + emergency focus
3. Focus session with body double
4. Medication adherence
5. Insights 7-day bars
6. You / Health / Sync

## Feature graphic
1024×500 — brand green accent on calm dark surface, wordmark “Look After”, tagline “Protect the quiet.”

## Data safety (summary)
- Collected: optional account id (Firebase), crash logs (Crashlytics when enabled), health metrics (Health Connect, on device), calendar events (read, on device)
- Shared: only with your configured LLM / Firebase project when you enable those integrations
- Encrypted in transit: yes (HTTPS)
- Users can request deletion: local uninstall + Firebase console delete when used
