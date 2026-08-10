# F5 checklist run — 2026-08-10

Automated pass from agent. Manual items remain **YOU**.

## Results

| Step | Result | Notes |
|------|--------|-------|
| Ship assets in repo | **PASS** | docs, listing, release notes, data safety, SVG, workflows |
| versionName / versionCode | **PASS** | `0.1.0` / `1` · `com.lookafter.app` |
| Privacy URL live | **FAIL** | `https://samaksh-clouddevops.github.io/Look-After/privacy` → **HTTP 404** |
| Site root live | **FAIL** | same host → **HTTP 404** |
| Pages API status | **Not enabled** | `GET /pages` → 404 "GitHub Pages not enabled" |
| Enable Pages via API | **FAIL** | token lacks admin; PUT `/pages` → 404 |
| Trigger `pages.yml` | **Done** | Run failed because Pages source not set in repo Settings |
| Local `bundleRelease` | **SKIP** | No JDK on this agent machine |
| CI Android build | **FAIL (latest)** | See Actions; need green `Android CI` for AAB artifact |
| CI AAB artifact download | **Blocked** | depends on green Android CI |
| Play Console upload | **YOU** | needs browser + Play account |
| Device smoke | **YOU** | needs physical/emulator install |

## What you must do (order)

### 1. Enable GitHub Pages (2 min)
1. Open https://github.com/samaksh-clouddevops/Look-After/settings/pages  
2. **Build and deployment → Source: GitHub Actions**  
3. Save  
4. Actions → **Deploy GitHub Pages** → **Run workflow** (branch `feature/android-implementation` or `main`)  
5. Confirm green, then open:  
   - https://samaksh-clouddevops.github.io/Look-After/  
   - https://samaksh-clouddevops.github.io/Look-After/privacy  

### 2. Get a green AAB (pick one)

**A — Fix CI (preferred)**  
1. Open latest failed **Android CI** run and fix the failing step  
2. Re-run workflow on `feature/android-implementation`  
3. Download artifact **`app-release-aab`**

**B — Local machine with JDK 17+**  
```powershell
cd android
.\gradlew.bat clean :app:bundleRelease
# → app\build\outputs\bundle\release\app-release.aab
```

### 3. Play Console internal track
1. Create/select app **Look After** · `com.lookafter.app`  
2. **App content → Privacy policy** = Pages privacy URL  
3. Data safety + content rating (docs in `android/store/play/`)  
4. Store listing text from `PLAY_LISTING.md`  
5. Feature graphic 1024×500 from `feature-graphic.svg`  
6. **Internal testing** → upload AAB → paste `release-notes.txt`  
7. Add tester emails → start rollout  

### 4. Smoke (30 min)
Use table in [F5_INTERNAL_RUNBOOK.md](F5_INTERNAL_RUNBOOK.md) §5.

## Gate status

| Gate | Status |
|------|--------|
| F5 code/docs materials | **MET** |
| F5 launch (privacy live + internal AAB + tester) | **NOT MET** — blocked on Pages enable + green AAB + Play upload |
