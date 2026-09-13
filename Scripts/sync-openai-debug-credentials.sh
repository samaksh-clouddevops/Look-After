#!/bin/bash
# Embeds OpenAI TTS key from ~/ADHD/credentials into the Debug app bundle so
# physical-device installs can use Cloud voice (Mac filesystem is not visible on device).
# Never embeds secrets into Release builds. Output is gitignored / build-product only.
set -euo pipefail

DEST_DIR="${TARGET_BUILD_DIR:-}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}"
if [[ -z "${DEST_DIR}" || "${DEST_DIR}" == "/" ]]; then
  echo "warning: build product resources path unavailable — skipping OpenAI debug credentials"
  exit 0
fi

DEST="${DEST_DIR}/OpenAI-Debug.plist"
mkdir -p "${DEST_DIR}"

if [[ "${CONFIGURATION:-Debug}" == "Release" ]]; then
  rm -f "${DEST}"
  echo "note: skipped OpenAI debug credentials for Release"
  exit 0
fi

CREDS=""
for candidate in \
  "${HOME}/ADHD/credentials" \
  "${SIMULATOR_HOST_HOME:-}/ADHD/credentials" \
  "/Users/samaksh/ADHD/credentials"
do
  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    CREDS="${candidate}"
    break
  fi
done

if [[ -z "${CREDS}" ]]; then
  rm -f "${DEST}"
  echo "note: no ~/ADHD/credentials — Cloud voice needs Settings → API Keys on device"
  exit 0
fi

export LOOKAFTER_CREDS_PATH="${CREDS}"
export LOOKAFTER_OPENAI_DEBUG_PLIST="${DEST}"

python3 - <<'PY'
import os, plistlib, pathlib, re

creds = pathlib.Path(os.environ["LOOKAFTER_CREDS_PATH"]).read_text(encoding="utf-8", errors="replace")
key = None
for line in creds.splitlines():
    raw = line.strip()
    if not raw or raw.startswith("#"):
        continue
    m = re.match(r"(?i)^(openai_api_key)\s*[:=]\s*(.+)$", raw)
    if m:
        key = m.group(2).strip().strip('"').strip("'")
        break

dest = pathlib.Path(os.environ["LOOKAFTER_OPENAI_DEBUG_PLIST"])
if not key:
    if dest.exists():
        dest.unlink()
    print("note: openai_api_key missing in credentials")
else:
    with dest.open("wb") as f:
        plistlib.dump({"openai_api_key": key}, f, sort_keys=False)
    print(f"Embedded OpenAI debug credentials for Cloud TTS ({len(key)} chars)")
PY
