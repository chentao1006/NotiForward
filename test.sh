#!/bin/bash
# Runs the checks and unit tests, then builds a Release copy, installs it to
# /Applications and launches it for manual testing.
#
# Usage: ./test.sh            checks + tests + install + launch
#        ./test.sh --no-install   checks + tests only

# Braces make bash read the whole script before running it, so editing this file
# while a run is in progress can't make the running copy read garbled lines.
{
set -eo pipefail
cd "$(dirname "$0")"

APP_NAME="NotiForward"
PROCESS_NAME="NotiForward"
SCHEME="NotiForward"
PROJECT="NotiForward.xcodeproj"
DERIVED_DATA_DIR="./build/DerivedData"
BUILT_APP_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"
LOG_DIR="./build/logs"

INSTALL=true
[ "$1" = "--no-install" ] && INSTALL=false
mkdir -p "${LOG_DIR}"

# Shows the tail of a failed xcodebuild log instead of the full output.
run_logged() {
    local log="$1"; shift
    if ! "$@" > "${log}" 2>&1; then
        grep -E "error:|✘|failed|FAILED" "${log}" | head -40 || tail -40 "${log}"
        echo "❌ Failed. Full log: ${log}"
        exit 1
    fi
}

echo "🧩 1. Generating Xcode project..."
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec project.yml --quiet
else
    echo "⚠️ xcodegen not found, using the committed ${PROJECT}."
fi

echo "🌐 2. Checking localizations..."
python3 scripts/localization.py check

echo "🧪 3. Running unit tests..."
run_logged "${LOG_DIR}/test.log" xcodebuild test \
    -project "${PROJECT}" -scheme "${SCHEME}" \
    -destination "platform=macOS" \
    -derivedDataPath "${DERIVED_DATA_DIR}"
grep -E "Test run with" "${LOG_DIR}/test.log" | tail -2 | sed 's/^/   /'

echo "🛍️ 4. Checking the App Store build..."
# App Review rejects temporary exceptions; they belong in the direct build only.
if grep -q "temporary-exception" NotiForward/NotiForwardAppStore.entitlements; then
    echo "❌ NotiForwardAppStore.entitlements must not contain temporary-exception entitlements"
    exit 1
fi
run_logged "${LOG_DIR}/appstore-build.log" xcodebuild build \
    -project "${PROJECT}" -scheme NotiForwardAppStore -configuration Debug \
    -destination "platform=macOS" -derivedDataPath "${DERIVED_DATA_DIR}-AppStore"
echo "   App Store target builds"

[ "${INSTALL}" = "true" ] || { echo "🎉 Checks and tests passed."; exit 0; }

echo "🏗️ 5. Building Release..."
run_logged "${LOG_DIR}/build.log" xcodebuild build \
    -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "${DERIVED_DATA_DIR}"
[ -d "${BUILT_APP_PATH}" ] || { echo "❌ ${BUILT_APP_PATH} not found"; exit 1; }

echo "🛑 6. Stopping running instance..."
pkill -x "${PROCESS_NAME}" || true
for _ in {1..10}; do
    pgrep -x "${PROCESS_NAME}" >/dev/null || break
    sleep 0.5
done

# The notification folder bookmark lives in the sandbox container, so it survives reinstalls.
echo "📦 7. Installing to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
cp -R "${BUILT_APP_PATH}" "${INSTALL_PATH}"
xattr -cr "${INSTALL_PATH}"

echo "🚀 8. Launching ${APP_NAME}..."
sleep 1
open "${INSTALL_PATH}"
echo "🎉 Done."

exit
}
