# Auth proxy verification checklist

## Local (completed by `scripts/smoke-local.sh`)

- [x] `/health` responds
- [x] Admin can mint UUID product keys
- [x] Redeem binds key to `dev:<uid>`
- [x] Second account cannot reuse the same key (409)
- [x] Unlicensed caller gets 403 on `/v1/ai/*`
- [x] Responses never include `GLM_API_KEY`

## Azure (run after deploy)

1. Deploy with `infra/deploy.sh` (min replicas = 0). GLM key is a Container App secret → `GLM_API_KEY`.
2. Set iOS `AuthProxyBaseURL` to `https://<containerAppFqdn>`.
3. Enable Apple + Google in Firebase console; configure URL schemes for Google OAuth.
4. Mint keys: `POST /v1/admin/keys` with `x-admin-key`.
5. On device: Sign in with Apple/Google → redeem UUID → use AI.
6. Capture a proxied chat request (Charles/Proxyman): Authorization is a **Firebase ID token**; body has prompts only; **no** z.ai API key on the device.

## Security invariants

| Surface | Must contain | Must NOT contain |
|---------|--------------|------------------|
| iOS binary / Keychain (licensed mode) | Firebase session | Master GLM key |
| Device → Auth proxy | Firebase Bearer + prompts | GLM API key |
| Auth proxy → z.ai | `GLM_API_KEY` from Container App secret | Client identity secrets beyond usage metering |
