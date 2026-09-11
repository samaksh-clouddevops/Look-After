# App Store Review notes — iOS 26 revamp

**Document ID:** REL-IOS26-J2  
**Use:** Paste into App Store Connect → App Review Information → Notes (edit demo account details before submit).

---

## What changed in this binary

Look After’s **minimum OS is iOS 26 / macOS 26**. Chrome uses system Liquid Glass (tab bar, Capture, sheets, docks). Content cards and timeline rows stay **opaque** for ADHD legibility. Scheduling / Brain / HealthKit math are unchanged.

## Licensing (not StoreKit IAP)

Cloud AI (planning / GLM / cloud TTS) is unlocked with a **product license key** redeemed through Look After’s Azure auth-proxy. This is **not** an In-App Purchase. The on-device `isLicensed` flag is a **local cache** only; the proxy returns 403 when the license is inactive. Provide the demo product key below for AI-gated flows.

## Requires

- **iOS 26** (iPhone)  
- **macOS 26** (Mac companion, if reviewing that binary)

## Demo account / access

```
Email: <REVIEWER_DEMO_EMAIL>
Password: <REVIEWER_DEMO_PASSWORD>
Product / license key (if AI gated): <REVIEWER_LICENSE_KEY>
```

If Sign in with Apple is enabled on the paid-team entitlement: use the demo Apple ID provided separately. Personal Team builds may omit Sign in with Apple — use email/password or the demo path above.

## Features that need device hardware

| Feature | How to review |
|---|---|
| HealthKit energy / sleep | Grant Health access when prompted; sample Watch data optional |
| Calendar scheduling | Grant calendar access; empty calendar still shows Capture / tasks |
| Microphone / speech Capture | Grant Mic + Speech Recognition; or type in Capture field |
| Location / weather chip | Optional; grant When In Use only if reviewing Today weather |
| Live Activities / Dynamic Island | Start Focus from Brain or “Start Focus” Control Center control |
| Widgets | Add “Next Step” / Energy widgets; complete a NOW task to restamp |

## Permission strings

These match `Info.plist` / `project.yml` — do not rewrite for review:

- **Health:** sleep, HR/HRV, steps, energy, exercise/stand, workouts, SpO₂, mindful, water, menstrual cycle (when Cycle enabled) → energy + scheduling  
- **Calendar:** free blocks + meeting-aware windows; write for scheduled tasks  
- **Microphone / Speech:** voice Capture → tasks, journal, notes  
- **Location (When In Use):** local weather chip only  

## Review path (5 minutes)

1. Launch → complete or skip onboarding if shown.  
2. **Briefing** — confirm opaque cards + glass header controls.  
3. **Today** — confirm NOW rail; complete or open a task.  
4. **Capture** (center tab) — add a short note; Save.  
5. Optional: Settings → license key → pin Now to Lock Screen; start Focus.

## Privacy

- App and widget ship `PrivacyInfo.xcprivacy` (required-reason APIs + collected-data categories). Align ASC nutrition labels with Health (incl. reproductive if Cycle is on), Calendar, Mic/Speech, account, and AI transcripts.

## Known follow-ups (non-blocking for chrome ship)

- Full Dynamic Type migration of all `ds*` fixed sizes is deferred; Briefing / Today / Capture / Focus critical paths scaled in Phase I.  
- StoreKit IAP path is intentionally not used in this binary; product-key model disclosed above.

## Contact

```
<ENGINEERING_CONTACT_EMAIL>
```
