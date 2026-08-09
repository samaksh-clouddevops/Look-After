#!/usr/bin/env bash
# Set Container App secrets after minimal deploy (keys are not stored in Bicep).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RG="${AZURE_RESOURCE_GROUP:-lookafter-auth-rg}"
OUTPUT_FILE="${OUTPUT_FILE:-$ROOT/infra/deploy-output.json}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$ROOT/../../../credentials}"
FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-lifeos-dummy}"

if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "Missing $OUTPUT_FILE — run ./infra/deploy.sh first."
  exit 1
fi

read_credential() {
  local key="$1"
  grep -E "^${key}:" "$CREDENTIALS_FILE" 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//' || true
}

login_azure() {
  local client_id client_secret tenant_id
  client_id="$(read_credential client_id)"
  client_secret="$(read_credential client_secret)"
  tenant_id="$(read_credential tenant_id)"
  if [[ -n "$client_id" && -n "$client_secret" && -n "$tenant_id" ]]; then
    echo "Logging in to Azure..."
    az login --service-principal -u "$client_id" -p "$client_secret" --tenant "$tenant_id" --output none
    return
  fi
  az account show --output none
}

APP_NAME="$(python3 -c "import json; print(json.load(open('$OUTPUT_FILE'))['containerAppName']['value'])")"

if [[ -f "$CREDENTIALS_FILE" ]]; then
  ADMIN_API_KEY="${ADMIN_API_KEY:-$(read_credential admin_api_key)}"
  GLM_API_KEY="${GLM_API_KEY:-$(read_credential glm_api_key)}"
  OPENAI_API_KEY="${OPENAI_API_KEY:-$(read_credential openai_api_key)}"
  FIREBASE_SERVICE_ACCOUNT_JSON="${FIREBASE_SERVICE_ACCOUNT_JSON:-$(read_credential firebase_service_account_json)}"
  PRODUCT_KEYS_JSON="${PRODUCT_KEYS_JSON:-$(read_credential product_keys_json)}"
fi

if [[ -z "${ADMIN_API_KEY:-}" ]]; then
  ADMIN_API_KEY="$(openssl rand -hex 32)"
  echo "Generated ADMIN_API_KEY (save as admin_api_key:... in ${CREDENTIALS_FILE})"
fi

if [[ -z "${GLM_API_KEY:-}" ]]; then
  echo "Set GLM_API_KEY or add glm_api_key:... to ${CREDENTIALS_FILE}"
  exit 1
fi

if [[ -z "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ]]; then
  FIREBASE_SERVICE_ACCOUNT_JSON="{\"type\":\"service_account\",\"project_id\":\"${FIREBASE_PROJECT_ID}\"}"
  echo "Using placeholder Firebase service account for ${FIREBASE_PROJECT_ID} (dev auth mode)."
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  OPENAI_API_KEY="bootstrap-openai-replace-me"
  echo "OPENAI_API_KEY not set — using bootstrap placeholder (cloud TTS disabled until replaced)."
fi

if [[ -z "${PRODUCT_KEYS_JSON:-}" ]]; then
  PRODUCT_KEY="$(python3 -c 'import uuid; print(str(uuid.uuid4()))')"
  PRODUCT_KEYS_JSON="[\"${PRODUCT_KEY}\"]"
  echo "Generated PRODUCT_KEYS_JSON with one key (save as product_keys_json:... in ${CREDENTIALS_FILE})"
fi

login_azure

SECRETS=(
  "admin-api-key=${ADMIN_API_KEY}"
  "glm-api-key=${GLM_API_KEY}"
  "openai-api-key=${OPENAI_API_KEY}"
  "firebase-sa=${FIREBASE_SERVICE_ACCOUNT_JSON}"
  "product-keys-json=${PRODUCT_KEYS_JSON}"
)

echo "Setting secrets on ${APP_NAME}..."
az containerapp secret set \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --secrets "${SECRETS[@]}" \
  --output none

echo "Activating new revision..."
az containerapp revision copy \
  --name "$APP_NAME" \
  --resource-group "$RG" \
  --output none

echo "Done. Secrets configured on ${APP_NAME}."
