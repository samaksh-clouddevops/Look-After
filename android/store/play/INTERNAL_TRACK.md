# Play internal testing track — ship checklist (F4/F5)

## A. GitHub Pages (privacy URL)
1. Repo **Settings → Pages → Source: GitHub Actions**
2. Ensure `.github/workflows/pages.yml` has run green on `main` or this branch
3. Verify:
   - https://samaksh-clouddevops.github.io/Look-After/
   - https://samaksh-clouddevops.github.io/Look-After/privacy
4. Paste privacy URL into Play Console **App content → Privacy policy**

## B. Build AAB
```powershell
cd android
.\gradlew.bat clean :app:bundleRelease
```
Artifact: `android/app/build/outputs/bundle/release/app-release.aab`

Optional signing (upload key):
```
LOOKAFTER_STORE_FILE=
LOOKAFTER_STORE_PASSWORD=
LOOKAFTER_KEY_ALIAS=
LOOKAFTER_KEY_PASSWORD=
```
Prefer **Play App Signing** (upload key → Google re-signs).

CI already runs `bundleRelease` in `android-build.yml` (unsigned unless secrets set).

## C. Play Console (internal track)
- [ ] App created · applicationId `com.lookafter.app`
- [ ] Privacy policy URL live
- [ ] Data safety form (`DATA_SAFETY.md`)
- [ ] Content rating IARC (`CONTENT_RATING.md`)
- [ ] Store listing text (`../PLAY_LISTING.md`)
- [ ] Feature graphic PNG 1024×500
- [ ] ≥2 phone screenshots (recommend 6–8)
- [ ] Target API 35 confirmed
- [ ] Upload AAB → **Internal testing** track
- [ ] Release notes (`release-notes.txt`)
- [ ] Add tester emails / Google Group
- [ ] Smoke install on physical device (Today → Brain plan → Focus → Modules)

## D. Post-upload smoke
- [ ] Cold start hydration
- [ ] Create task · complete swipe · med toggle
- [ ] Briefing begin focus
- [ ] Deny Health / Calendar still loads demo
- [ ] Export backup · factory reset (tester only)
- [ ] Body-double demo join (optional)

## E. Version
`versionName` 0.1.0 · `versionCode` 1 — bump before each Play upload.
