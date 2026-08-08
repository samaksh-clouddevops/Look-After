# Build a Play upload bundle (AAB)

## Prerequisites
1. JDK 17+
2. Android SDK 35
3. Optional release keystore env:

```bash
export LOOKAFTER_STORE_FILE=/secure/path/upload.jks
export LOOKAFTER_STORE_PASSWORD=...
export LOOKAFTER_KEY_ALIAS=lookafter
export LOOKAFTER_KEY_PASSWORD=...
```

4. Optional Firebase: place `android/app/google-services.json`
5. Optional LLM: `LOOKAFTER_LLM_API_KEY` in `android/local.properties`

## Commands

From repo root:

```bash
cd android
./gradlew clean :app:bundleRelease
```

Windows:

```powershell
cd android
.\gradlew.bat clean :app:bundleRelease
```

Output:

```
android/app/build/outputs/bundle/release/app-release.aab
```

## Play Console checklist
- [ ] Create app · package `com.lookafter.app`
- [ ] Privacy policy URL (GitHub Pages)
- [ ] Data safety form (`DATA_SAFETY.md`)
- [ ] Store listing (`../PLAY_LISTING.md`)
- [ ] Screenshots · feature graphic 1024×500
- [ ] Content rating questionnaire
- [ ] Target API 35 · app signing by Google Play
- [ ] Upload AAB to internal testing track first
- [ ] Release notes (`release-notes.txt`)

## CI
GitHub Actions `android-build.yml` already runs unit tests, `assembleDebug`, and `assembleRelease`.
Add a manual `bundleRelease` job when upload keys are in GitHub Secrets.
