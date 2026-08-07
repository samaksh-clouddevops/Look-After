# Firebase setup (optional)

Look After builds **without** Firebase. When you add a project:

1. Create an Android app in Firebase Console (`com.lookafter.app`).
2. Download `google-services.json` → place at `android/app/google-services.json`.
3. Re-sync Gradle — Auth, Firestore, and Crashlytics dependencies enable automatically.
4. Enable **Anonymous Auth** (and Email/Password if desired).
5. Create Firestore in production mode; rules example:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/meta/{doc} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

6. Enable Crashlytics in the console.

## LLM planner

In `android/local.properties`:

```
LOOKAFTER_LLM_API_KEY=sk-...
LOOKAFTER_LLM_BASE_URL=https://api.openai.com/v1
LOOKAFTER_LLM_MODEL=gpt-4o-mini
```

Brain chat messages that look like plans request JSON `PlanProposal` mutations.

## Play release signing

```
LOOKAFTER_STORE_FILE=/path/to/upload.jks
LOOKAFTER_STORE_PASSWORD=...
LOOKAFTER_KEY_ALIAS=...
LOOKAFTER_KEY_PASSWORD=...
```
