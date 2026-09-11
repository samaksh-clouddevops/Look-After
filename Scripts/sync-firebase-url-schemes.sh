#!/bin/bash
# Syncs Firebase / Google Sign-In URL schemes + GIDClientID from GoogleService-Info.plist
# into the built Info.plist. Idempotent — safe under parallel/repeated Xcode script runs.
set -euo pipefail

SRC_PLIST="${SRCROOT}/Config/GoogleService-Info.plist"
INFO_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if [[ ! -f "$SRC_PLIST" ]]; then
  echo "note: GoogleService-Info.plist missing — skipping OAuth URL scheme sync"
  exit 0
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "warning: Built Info.plist not found at $INFO_PLIST"
  exit 0
fi

GOOGLE_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :GOOGLE_APP_ID" "$SRC_PLIST" 2>/dev/null || true)
REVERSED_CLIENT_ID=$(/usr/libexec/PlistBuddy -c "Print :REVERSED_CLIENT_ID" "$SRC_PLIST" 2>/dev/null || true)
CLIENT_ID=$(/usr/libexec/PlistBuddy -c "Print :CLIENT_ID" "$SRC_PLIST" 2>/dev/null || true)

SCHEMES=()
if [[ -n "${GOOGLE_APP_ID}" ]]; then
  SCHEMES+=("app-${GOOGLE_APP_ID//:/-}")
fi
if [[ -n "${REVERSED_CLIENT_ID}" ]]; then
  SCHEMES+=("${REVERSED_CLIENT_ID}")
fi
SCHEMES+=("lookafter")

UNIQUE_SCHEMES=()
for s in "${SCHEMES[@]}"; do
  skip=0
  for u in "${UNIQUE_SCHEMES[@]:-}"; do
    [[ "$u" == "$s" ]] && skip=1 && break
  done
  [[ $skip -eq 0 ]] && UNIQUE_SCHEMES+=("$s")
done

# Atomic rewrite via Python so partial/parallel PlistBuddy Adds cannot fail the build.
export LOOKAFTER_SYNC_INFO_PLIST="$INFO_PLIST"
export LOOKAFTER_SYNC_CLIENT_ID="${CLIENT_ID:-}"
export LOOKAFTER_SYNC_SCHEMES="$(printf '%s\n' "${UNIQUE_SCHEMES[@]}")"

python3 - <<'PY'
import os, plistlib

path = os.environ["LOOKAFTER_SYNC_INFO_PLIST"]
client_id = os.environ.get("LOOKAFTER_SYNC_CLIENT_ID") or ""
schemes = [s for s in os.environ.get("LOOKAFTER_SYNC_SCHEMES", "").split("\n") if s]

with open(path, "rb") as f:
    info = plistlib.load(f)

oauth_schemes = [s for s in schemes if s != "lookafter"]
info["CFBundleURLTypes"] = [
    {
        "CFBundleURLName": "com.samaksh.flowos.app.lookafter",
        "CFBundleURLSchemes": ["lookafter"],
    },
    {
        "CFBundleURLName": "com.samaksh.flowos.app.firebase-oauth",
        "CFBundleURLSchemes": oauth_schemes,
    },
]
if client_id:
    info["GIDClientID"] = client_id

with open(path, "wb") as f:
    plistlib.dump(info, f, sort_keys=False)

print("Synced Google Sign-In URL schemes:", " ".join(schemes))
PY
