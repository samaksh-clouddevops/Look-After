# Play Console — Data safety answers (draft)

## Does your app collect or share user data?
**Yes** (when optional features are enabled). Core experience works fully offline/local.

## Data types

| Type | Collected | Shared | Purpose | Required |
|------|-----------|--------|---------|----------|
| App activity (tasks, focus) | Yes (on device) | Only if cloud sync/LLM enabled by developer | App functionality | Yes for core |
| Health & fitness | Optional (Health Connect) | No by default | App functionality | No |
| Calendar | Optional | No by default | App functionality | No |
| Photos/videos (camera preview) | Ephemeral preview only | No | App functionality (body double) | No |
| Audio (mic for WebRTC room) | Optional future | Signaling only if configured | App functionality | No |
| Personal info (name/email) | Optional Firebase Auth | With your Firebase project | Account management | No |
| App info & performance (crashes) | Optional Crashlytics | Google/Firebase if enabled | Analytics/stability | No |

## Security practices
- Data encrypted in transit (HTTPS) for LLM / Firebase
- Users can request deletion: uninstall + Firebase console
- Committed to Play Families policy: **No** (not primarily for children)

## Privacy policy URL
https://samaksh-clouddevops.github.io/Look-After/privacy
