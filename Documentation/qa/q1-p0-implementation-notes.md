# Q1 P0 implementation notes (feature-preserving)

## Intentionally not implemented / reverted (would restrict product behavior)

1. **EventKit `.writeOnly` ≠ readable** — Reverted. Calendar free-block / briefing reads still treat `.writeOnly` as authorized (prior behavior). Prefer Full Access in UX, but do not lock out write-only users.
2. **HealthKit `enableBackgroundDelivery` gated off** — Reverted. Calls remain so background observer behavior is unchanged; failures are DEBUG-logged when the entitlement is missing.
3. **StoreKit / IAP path** — Deferred by plan (product-key retained). Not a feature removal.
4. **Softening Firebase to fake-auth on failure** — Not restored. Email/create still require real Firebase Auth success (removes only the broken “signed in with unstable `hashValue` UID” path). Guest Keychain + real anon still work. Device golden T-01–T-37 checklist only (no Brain rewrite).

## Shipped in this pass (non-restrictive)

- Firebase await Auth + stable guest Keychain UID + nil-user listener (keeps local guest session)
- PrivacyInfo (app + widget), aligned Health + Location usage strings
- License docs + UD-as-cache + foreground `refreshStatus`
- Medication FileProtection migrate; LocalPersistenceManager protection; `geminiApiKey` not encoded on UserProfile (Keychain/proxy unchanged)
- Gmail Keychain add-or-update + delete on disconnect
- Task sync outbox MVP + BG/foreground drain
- Speech tap local request; sleep FallbackGradient Reduce Motion
- Tests: auth, EventKit helper (prior behavior), outbox, license, widget fingerprint force gate, timeline complete/uncomplete, auth-proxy fail-closed
