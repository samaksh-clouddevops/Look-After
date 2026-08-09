# Look After Auth Proxy

License + GLM proxy for Azure Container Apps. Master LLM keys live in a **Container App secret** (`glm-api-key` → env `GLM_API_KEY`). Clients never receive them.

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | none | Liveness |
| POST | `/v1/admin/keys` | `x-admin-key` | Mint product UUIDs `{ "count": 5 }` |
| POST | `/v1/license/redeem` | Firebase Bearer | `{ "productKey": "<uuid>" }` |
| GET | `/v1/license/status` | Firebase Bearer | License status for caller |
| POST | `/v1/ai/chat` | Firebase Bearer + license | Proxied chat completion |
| POST | `/v1/ai/complete` | Firebase Bearer + license | Proxied structured completion |
| POST | `/v1/ai/speech` | Firebase Bearer + license | Proxied OpenAI TTS (`audio/mpeg`) |

## Local run

```bash
cp .env.example .env
# set FIREBASE_PROJECT_ID, ADMIN_API_KEY, GLM_API_KEY
npm install
npm run dev
```

## Docker

```bash
docker build -t lookafter-auth-proxy .
docker run --rm -p 8080:8080 --env-file .env lookafter-auth-proxy
```

## Azure deploy

See [`infra/README.md`](infra/README.md) and `infra/deploy.sh`. GLM key is passed as a Container App secret, not Key Vault.
