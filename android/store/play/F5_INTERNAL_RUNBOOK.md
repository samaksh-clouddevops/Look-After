# F5 — Internal track runbook (0.1.0)

Use with [INTERNAL_TRACK.md](INTERNAL_TRACK.md). Check boxes as you go.

## 1. GitHub Pages (privacy)

- [ ] Repo → **Settings → Pages → Source: GitHub Actions**
- [ ] Actions: workflow **Deploy GitHub Pages** green on `feature/android-implementation` or `main`
- [ ] Open https://samaksh-clouddevops.github.io/Look-After/
- [ ] Open https://samaksh-clouddevops.github.io/Look-After/privacy
- [ ] Paste privacy URL into Play Console **App content → Privacy policy**

## 2. Local AAB

```powershell
cd android
.\gradlew.bat clean :app:bundleRelease
```

- [ ] Artifact exists: `android/app/build/outputs/bundle/release/app-release.aab`
- [ ] Size > 0 (expect tens of MB with WebRTC AAR)
- [ ] If keystore env vars set → signed; else CI/Play may re-sign or reject — use **Play App Signing**

Optional env (upload key):

```
LOOKAFTER_STORE_FILE
LOOKAFTER_STORE_PASSWORD
LOOKAFTER_KEY_ALIAS
LOOKAFTER_KEY_PASSWORD
```

## 3. Play Console — create / configure

- [ ] App: **Look After** · package `com.lookafter.app`
- [ ] Free · Productivity
- [ ] Data safety (`DATA_SAFETY.md`) submitted
- [ ] Content rating IARC (`CONTENT_RATING.md`)
- [ ] Target audience 18+ / not primarily children
- [ ] Store listing from `../PLAY_LISTING.md`
- [ ] Feature graphic 1024×500 (export `feature-graphic.svg`)
- [ ] ≥2 phone screenshots (prefer 6–8 from listing order)

## 4. Internal testing track

- [ ] **Release → Testing → Internal testing → Create release**
- [ ] Upload `app-release.aab`
- [ ] Paste `release-notes.txt`
- [ ] Review → **Start rollout to Internal testing**
- [ ] Testers: email list or Google Group
- [ ] Copy internal testing link / opt-in URL to testers

## 5. Device smoke (30 min)

| Area | Pass? |
|------|-------|
| Cold start · hydration subtitle clears | [ ] |
| Today: create · swipe complete · park · week day | [ ] |
| Briefing: Begin focus | [ ] |
| Brain: ask plan · Accept/Discard | [ ] |
| Focus timer · complete | [ ] |
| Meds strip / Medication screen | [ ] |
| Health: 7-day bars (demo OK) | [ ] |
| Insights opens | [ ] |
| Modules: Travel · Learning · Habits open | [ ] |
| Body-double: Create + Demo join | [ ] |
| Privacy: Export share sheet | [ ] |
| Deny calendar/health still usable | [ ] |

## 6. Done criteria (F5 gate)

- [ ] Privacy URL public HTTPS
- [ ] AAB on internal track
- [ ] ≥1 external tester install successful
- [ ] No crash on first 10 min of critical path

## 7. Version bump before next upload

`android/app/build.gradle.kts` → increment `versionCode` / `versionName`.
