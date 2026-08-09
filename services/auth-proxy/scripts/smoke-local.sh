#!/usr/bin/env bash
# Local smoke test without Azure/Firebase. Does not call real GLM (no key needed for redeem path).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PORT=18080
export FIREBASE_PROJECT_ID=dev-project
export ADMIN_API_KEY=dev-admin-key
export AUTH_DEV_ALLOW_INSECURE=true
export DATA_DIR="$ROOT/data-smoke"
export GLM_API_KEY="${GLM_API_KEY:-}"
rm -rf "$DATA_DIR"

npm run build >/dev/null
node dist/index.js &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
sleep 1

echo "== health =="
curl -sf "http://127.0.0.1:${PORT}/health" | grep -q '"ok":true'

echo "== mint keys =="
KEYS_JSON=$(curl -sf -X POST "http://127.0.0.1:${PORT}/v1/admin/keys" \
  -H "x-admin-key: ${ADMIN_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"count":1}')
KEY=$(node -e "const j=JSON.parse(process.argv[1]); if(!j.keys?.[0]) process.exit(1); process.stdout.write(j.keys[0])" "$KEYS_JSON")
echo "minted $KEY"

echo "== redeem =="
curl -sf -X POST "http://127.0.0.1:${PORT}/v1/license/redeem" \
  -H "Authorization: Bearer dev:user-a" \
  -H "Content-Type: application/json" \
  -d "{\"productKey\":\"$KEY\"}" | grep -q '"active":true'

echo "== status =="
curl -sf "http://127.0.0.1:${PORT}/v1/license/status" \
  -H "Authorization: Bearer dev:user-a" | grep -q '"active":true'

echo "== second user cannot reuse key =="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${PORT}/v1/license/redeem" \
  -H "Authorization: Bearer dev:user-b" \
  -H "Content-Type: application/json" \
  -d "{\"productKey\":\"$KEY\"}")
test "$CODE" = "409"

echo "== AI without license rejected =="
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${PORT}/v1/ai/chat" \
  -H "Authorization: Bearer dev:user-b" \
  -H "Content-Type: application/json" \
  -d '{"message":"hi","model":"glm-4.7-flash"}')
test "$CODE" = "403"

echo "SMOKE OK (license binding + auth gates verified; GLM upstream skipped without key)"
