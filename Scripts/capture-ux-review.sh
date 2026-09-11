#!/usr/bin/env bash
# Capture the full Look After functionality flow (step screenshots) for UI/UX agent review.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEST="${ROOT}/screenshots/ux-agent"
mkdir -p "${DEST}/latest"
rm -rf "${DEST}/latest"/* "${DEST}/crops" 2>/dev/null || true
mkdir -p "${DEST}/latest" "${DEST}/crops"

DEVICE="${LOOKAFTER_SIMULATOR_DEVICE:-iPhone 17}"
OS="${LOOKAFTER_SIMULATOR_OS:-26.5}"
DESTINATION="platform=iOS Simulator,name=${DEVICE},OS=${OS}"

# Mode: flow (default) | core | both
MODE="${LOOKAFTER_UX_CAPTURE_MODE:-flow}"

echo "→ Regenerating project (if needed)"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null

# Pre-grant mic/speech so Brain/Capture never block the run on system alerts.
BUNDLE_ID="com.samaksh.flowos.app"
if xcrun simctl list devices booted | grep -q Booted; then
  xcrun simctl privacy booted grant microphone "${BUNDLE_ID}" 2>/dev/null || true
  xcrun simctl privacy booted grant speech-recognition "${BUNDLE_ID}" 2>/dev/null || true
  xcrun simctl privacy booted grant speech "${BUNDLE_ID}" 2>/dev/null || true
fi

export LOOKAFTER_REPO_ROOT="${ROOT}"
export LOOKAFTER_EXPORT_UX_REVIEW=1
export TEST_RUNNER_LOOKAFTER_EXPORT_UX_REVIEW=1
export TEST_RUNNER_LOOKAFTER_REPO_ROOT="${ROOT}"

run_test() {
  local only="$1"
  echo "→ Running ${only} on ${DESTINATION}"
  xcodebuild \
    -scheme LookAfter-iOS \
    -destination "${DESTINATION}" \
    -only-testing:"${only}" \
    test \
    2>&1 | tee /tmp/lookafter-ux-capture.log | tail -80
}

case "${MODE}" in
  core)
    run_test "LookAfterSnapshotTests/UXAgentCaptureUITests/testExportCoreScreensForUXAgent"
    ;;
  both)
    run_test "LookAfterSnapshotTests/UXAgentCaptureUITests/testExportFullFunctionalityFlowForUXAgent"
    # Core would wipe latest/ — skip unless explicitly forced.
    echo "→ Note: both mode runs flow only (core would overwrite latest/). Use MODE=core separately if needed."
    ;;
  flow|*)
    run_test "LookAfterSnapshotTests/UXAgentCaptureUITests/testExportFullFunctionalityFlowForUXAgent"
    ;;
esac

echo ""
echo "→ Screenshots:"
ls -la "${DEST}/latest" || true
echo ""
echo "Open MANIFEST: ${DEST}/latest/MANIFEST.md"
echo "Ask Cursor: review screenshots/ux-agent/latest with ui-ux-pro-max (full flow F01–F19)"
