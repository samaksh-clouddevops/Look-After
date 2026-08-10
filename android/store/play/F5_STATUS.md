# F5 status — internal track readiness (0.1.0)

## Automated / in-repo (done)

| Item | Status |
|------|--------|
| Privacy policy HTML | Done (`docs/privacy.html`) |
| Landing site | Done (`docs/index.html`) |
| Pages workflow | Done (`.github/workflows/pages.yml`) |
| Play listing draft | Done (`PLAY_LISTING.md`) |
| Release notes | Done (`release-notes.txt`) |
| Data safety / content rating docs | Done |
| Feature graphic SVG | Done |
| CI unit tests + assemble + **bundleRelease** | Done (`android-build.yml` uploads AAB artifact) |
| AAB local instructions | Done (`BUILD_AAB.md`, `INTERNAL_TRACK.md`, `F5_INTERNAL_RUNBOOK.md`) |
| versionName / versionCode | `0.1.0` / `1` |

## Operator / console (manual — you)

These cannot be completed from the agent without your GitHub org + Play accounts:

1. **Enable GitHub Pages** (Settings → Pages → GitHub Actions)  
2. **Confirm live privacy URL**  
3. **Download AAB** from Actions artifact `app-release-aab` *or* local `bundleRelease`  
4. **Play Console** app create + data safety + content rating + listing  
5. **Internal testing** upload + tester list  
6. **Device smoke** per runbook  

## Links

- Runbook: [F5_INTERNAL_RUNBOOK.md](F5_INTERNAL_RUNBOOK.md)  
- Privacy (after Pages): https://samaksh-clouddevops.github.io/Look-After/privacy  
- CI AAB artifact: Actions → Android Build → `app-release-aab`  

## F5 gate definition

Code/docs gate for F5 is **met** when materials + CI AAB path exist.  
**Launch gate** is met when privacy is live **and** ≥1 internal tester installs the AAB.
