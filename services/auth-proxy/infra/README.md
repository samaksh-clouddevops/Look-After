# Azure infra for Look After Auth Proxy (minimal)

## Resources (Bicep)

- Container Apps Environment (consumption, no Log Analytics)
- Container App (0.25 vCPU / 0.5Gi, min replicas 0)
- Docker Hub private image pull credentials (registry secret only)

**Not provisioned:** ACR, Storage Account, Log Analytics. License data uses ephemeral file storage under `/tmp/lookafter-data` (resets on cold start / new replica).

## Secrets (you manage in Container App)

| Secret name | Env var |
|-------------|---------|
| `admin-api-key` | `ADMIN_API_KEY` |
| `glm-api-key` | `GLM_API_KEY` |
| `openai-api-key` | `OPENAI_API_KEY` (cloud voice / TTS) |
| `firebase-sa` | `FIREBASE_SERVICE_ACCOUNT_JSON` |
| `product-keys-json` | `PRODUCT_KEYS_JSON` |

`PRODUCT_KEYS_JSON` is a JSON allowlist of product key UUIDs:

```json
["550e8400-e29b-41d4-a716-446655440000", "6ba7b810-9dad-11d1-80b4-00c04fd430c8"]
```

Or `{ "keys": ["uuid-here"] }`. Mint locally with `/v1/admin/keys`, then paste into the secret.

Bootstrap placeholders are deployed first; replace with real values:

```bash
ADMIN_API_KEY="$(openssl rand -hex 32)" \
GLM_API_KEY='your-glm-key' \
OPENAI_API_KEY='your-openai-key' \
FIREBASE_SERVICE_ACCOUNT_JSON="$(cat service-account.json | jq -c .)" \
PRODUCT_KEYS_JSON='["550e8400-e29b-41d4-a716-446655440000"]' \
./infra/configure-secrets.sh
```

## Deploy

```bash
chmod +x infra/deploy.sh infra/configure-secrets.sh
ALLOW_INSECURE_DEV_AUTH=true ./infra/deploy.sh   # dev only
```

## Remove orphaned ACR (from earlier deploys)

```bash
az acr delete --name lookafteracr2a9c75b6 --resource-group lookafter-auth-rg --yes
```

## Smoke test

```bash
curl -s "https://<fqdn>/health"
```
