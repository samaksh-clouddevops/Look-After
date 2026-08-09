#!/usr/bin/env bash
# Minimal deploy: Docker Hub image + Container Apps only (no ACR, Storage, Log Analytics).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RG="${AZURE_RESOURCE_GROUP:-lookafter-auth-rg}"
LOC="${AZURE_LOCATION:-eastus}"
IMAGE_NAME="${IMAGE_NAME:-lookafter-auth-proxy}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$ROOT/../../../credentials}"

FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-lifeos-dummy}"
ALLOW_INSECURE_DEV_AUTH="${ALLOW_INSECURE_DEV_AUTH:-false}"

read_credential() {
  local key="$1"
  grep -E "^${key}:" "$CREDENTIALS_FILE" 2>/dev/null | cut -d: -f2- | tr -d '[:space:]' || true
}

read_dockerhub_credentials() {
  DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-$(read_credential dockerhub_username)}"
  DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-$(read_credential dockerhub_token)}"

  if [[ -z "$DOCKERHUB_USERNAME" || -z "$DOCKERHUB_TOKEN" ]] && [[ -f "$CREDENTIALS_FILE" ]]; then
    local login_line
    login_line="$(grep -E 'docker login -u ' "$CREDENTIALS_FILE" 2>/dev/null | head -1 || true)"
    if [[ -n "$login_line" ]]; then
      DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-$(echo "$login_line" | awk '{print $4}')}"
      DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-$(echo "$login_line" | awk '{print $5}')}"
    fi
  fi

  if [[ -z "$DOCKERHUB_USERNAME" || -z "$DOCKERHUB_TOKEN" ]]; then
    echo "Missing Docker Hub credentials in ${CREDENTIALS_FILE}"
    exit 1
  fi
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

remove_orphan_acr() {
  local acr
  for acr in $(az acr list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null); do
    echo "Removing unused ACR: ${acr}"
    az acr delete --name "$acr" --resource-group "$RG" --yes --output none
  done
}

build_and_push_dockerhub() {
  local image="${DOCKERHUB_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null
  docker build --platform linux/amd64 -t "$image" "$ROOT"
  docker push "$image"
  CONTAINER_IMAGE="$image"
}

echo "==> Look After auth-proxy (minimal Azure footprint)"
read_dockerhub_credentials
login_azure

echo "Creating resource group ${RG}..."
az group create --name "$RG" --location "$LOC" >/dev/null

remove_orphan_acr
build_and_push_dockerhub

echo "Deploying Container App..."
OUTPUT_FILE="$ROOT/infra/deploy-output.json"
az deployment group create \
  --resource-group "$RG" \
  --template-file "$ROOT/infra/main.bicep" \
  --parameters \
    containerImage="$CONTAINER_IMAGE" \
    firebaseProjectId="$FIREBASE_PROJECT_ID" \
    allowInsecureDevAuth="$ALLOW_INSECURE_DEV_AUTH" \
    dockerHubUsername="$DOCKERHUB_USERNAME" \
    dockerHubPassword="$DOCKERHUB_TOKEN" \
    minReplicas=0 \
  --query "properties.outputs" \
  --output json | tee "$OUTPUT_FILE"

APP_NAME="$(python3 -c "import json; print(json.load(open('$OUTPUT_FILE'))['containerAppName']['value'])")"

FQDN="$(python3 -c "import json; print(json.load(open('$OUTPUT_FILE'))['containerAppFqdn']['value'])")"
echo ""
echo "Deployed: https://${FQDN}"
echo "Image: ${CONTAINER_IMAGE}"
echo ""
echo "Set real secrets:"
echo "  ADMIN_API_KEY=... GLM_API_KEY=... OPENAI_API_KEY=... FIREBASE_SERVICE_ACCOUNT_JSON='...' \\"
echo "  PRODUCT_KEYS_JSON='[\"uuid-here\"]' ./infra/configure-secrets.sh"
echo ""
echo "Health (after secrets configured):"
curl -fsS "https://${FQDN}/health" | python3 -m json.tool || echo "(health may fail until secrets are set)"
