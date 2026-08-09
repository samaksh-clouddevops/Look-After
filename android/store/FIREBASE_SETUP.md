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

## LLM planner + streaming coach

In `android/local.properties`:

```
LOOKAFTER_LLM_API_KEY=sk-...
LOOKAFTER_LLM_BASE_URL=https://api.openai.com/v1
LOOKAFTER_LLM_MODEL=gpt-4o-mini
```

Brain chat streams assistant tokens via SSE when the key is set.
Plan-like messages still request JSON `PlanProposal` mutations (accept/reject in UI).

## WebRTC (native body double)

App depends on `io.getstream:stream-webrtc-android` for real peer media.
Defaults use public Google STUN. For symmetric NATs:

```
LOOKAFTER_TURN_URL=turn:turn.example.com:3478
LOOKAFTER_TURN_USER=user
LOOKAFTER_TURN_PASS=secret
LOOKAFTER_TURN_FORCE_RELAY=false
```

Room flow: You → Body double room → Create / Join → share code → second device Join.
UI shows backend `native` vs `simulator` and signaling `firestore` vs `local-file`.

### Signaling (C2)
- **Firestore** (when `google-services.json` present): collection `lookafter_rooms/{roomId}` field `envelope` (JSON).
- **Local file** (default offline): `filesDir/webrtc-rooms/{roomId}.json` polled ~400ms.
- Demo partner button still does local loopback without a second device.

CAMERA permission required for local video track.
Rules sketch for Firestore rooms:

```
match /lookafter_rooms/{roomId} {
  allow read, write: if request.auth != null;
}
```

## Play release signing

```
LOOKAFTER_STORE_FILE=/path/to/upload.jks
LOOKAFTER_STORE_PASSWORD=...
LOOKAFTER_KEY_ALIAS=...
LOOKAFTER_KEY_PASSWORD=...
```
