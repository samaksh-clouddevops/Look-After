#!/usr/bin/env bash
# Creates local Firebase config from the committed dummy template when missing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLIST="Config/GoogleService-Info.plist"
EXAMPLE="Config/GoogleService-Info.plist.example"

if [[ ! -f "$PLIST" ]]; then
  cp "$EXAMPLE" "$PLIST"
  echo "Created $PLIST from example (offline/mock Firebase)."
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
  echo "Regenerated LookAfter.xcodeproj"
else
  echo "Install XcodeGen: brew install xcodegen"
fi
