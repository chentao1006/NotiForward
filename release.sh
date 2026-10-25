#!/bin/bash
# Bumps the version, builds a Developer ID signed (and, with credentials, notarized)
# DMG, then commits, tags and publishes a GitHub release.
#
# Usage: ./release.sh [version] [--skip-build] [--no-publish] [--app-store]
#   version       new marketing version; prompted for when omitted, empty keeps the current one
#   --skip-build  reuse dist/NotiForward.dmg and the current version
#   --no-publish  stop after building (no git or GitHub steps)
#   --app-store   also archive the NotiForwardAppStore target and upload it to
#                 App Store Connect (uses the Apple ID signed in to Xcode)
#
# Notarization needs APPLE_ID and APPLE_PASSWORD (an app-specific password). Publishing an
# un-notarized build is refused, since Gatekeeper would block it; ALLOW_UNNOTARIZED=1 overrides.
# After the GitHub release, the Homebrew cask is updated (SKIP_HOMEBREW_RELEASE=1 skips it).

# Braces make bash read the whole script before running it, so editing this file
# while a run is in progress can't make the running copy read garbled lines.
{
set -eo pipefail
cd "$(dirname "$0")"

APP_NAME="NotiForward"
SCHEME="NotiForward"
PROJECT="NotiForward.xcodeproj"
TEAM_ID="U2NEAJ73J2"
RESULT_DIR="./dist"
ARCHIVE_PATH="${RESULT_DIR}/NotiForward.xcarchive"
EXPORT_PATH="${RESULT_DIR}/exported"
DMG_PATH="${RESULT_DIR}/NotiForward.dmg"

current_setting() { sed -nE "s/^ *$1: *\"?([^\"]*)\"?$/\1/p" project.yml | head -1; }
CURRENT_VERSION=$(current_setting MARKETING_VERSION)
CURRENT_BUILD=$(current_setting CURRENT_PROJECT_VERSION)

SKIP_BUILD=false
PUBLISH=true
APP_STORE=false
NEW_VERSION=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--skip-build) SKIP_BUILD=true ;;
        --no-publish) PUBLISH=false ;;
        --app-store) APP_STORE=true ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *) NEW_VERSION="$1" ;;
    esac
    shift
done

echo "----------------------------------------"
echo "Current Version: ${CURRENT_VERSION} (Build ${CURRENT_BUILD})"
echo "----------------------------------------"

# Apple's notary upload occasionally times out on a flaky connection with nothing wrong with the
# artifact, so retry a few times. `--wait` can exit 0 for an Invalid submission, so check the status.
notarize() {
    local path="$1" attempt output
    for attempt in 1 2 3; do
        echo "🔐 Submitting $(basename "${path}") for notarization (attempt ${attempt}/3)..."
        if output=$(xcrun notarytool submit "${path}" \
            --apple-id "${APPLE_ID}" --password "${APPLE_PASSWORD}" --team-id "${TEAM_ID}" --wait 2>&1); then
            echo "${output}" | tail -3
            if echo "${output}" | grep -q "status: Accepted"; then
                return 0
            fi
            echo "❌ Notarization was not accepted. Inspect it with: xcrun notarytool log <submission-id>"
            return 1
        fi
        echo "${output}" | tail -3
        [ "${attempt}" -lt 3 ] && { echo "⚠️ Submission failed, retrying in 30s..."; sleep 30; }
    done
    echo "❌ notarytool submit failed after 3 attempts."
    return 1
}

NOTARIZED=false

if [ "${SKIP_BUILD}" = "true" ]; then
    NEW_VERSION="${NEW_VERSION:-$CURRENT_VERSION}"
    NEW_BUILD="${CURRENT_BUILD}"
    [ -f "${DMG_PATH}" ] || { echo "❌ ${DMG_PATH} not found"; exit 1; }
    xcrun stapler validate "${DMG_PATH}" >/dev/null 2>&1 && NOTARIZED=true
    echo "⏩ Skipping build, releasing ${NEW_VERSION} (Build ${NEW_BUILD})."
else
    [ -n "${NEW_VERSION}" ] || read -r -p "Enter NEW Version (leave empty to keep current ${CURRENT_VERSION}): " NEW_VERSION
    if [ -z "${NEW_VERSION}" ]; then
        NEW_VERSION="${CURRENT_VERSION}"
        echo "Keeping current version: ${NEW_VERSION}"
    fi
    NEW_BUILD=$((CURRENT_BUILD + 1))
    echo "🚀 Preparing ${NEW_VERSION} (Build ${NEW_BUILD})..."

    # 1. Update version and regenerate the project
    sed -i '' -E "s/^( *MARKETING_VERSION: *).*/\1${NEW_VERSION}/" project.yml
    sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: *).*/\1${NEW_BUILD}/" project.yml
    if command -v xcodegen >/dev/null 2>&1; then
        xcodegen generate --spec project.yml --quiet
    else
        sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${NEW_VERSION};/" "${PROJECT}/project.pbxproj"
        sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/" "${PROJECT}/project.pbxproj"
    fi

    # 2. Checks and tests
    ./test.sh --no-install

    # 3. Archive and export with Developer ID
    rm -rf "${RESULT_DIR}"
    mkdir -p "${RESULT_DIR}"
    echo "📦 Archiving..."
    xcodebuild archive -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release \
        -destination "generic/platform=macOS" -archivePath "${ARCHIVE_PATH}" \
        ENABLE_HARDENED_RUNTIME=YES > "${RESULT_DIR}/archive.log" 2>&1 \
        || { tail -40 "${RESULT_DIR}/archive.log"; exit 1; }
    echo "📤 Exporting..."
    xcodebuild -exportArchive -archivePath "${ARCHIVE_PATH}" \
        -exportOptionsPlist ExportOptions.plist -exportPath "${EXPORT_PATH}" \
        -allowProvisioningUpdates > "${RESULT_DIR}/export.log" 2>&1 \
        || { tail -40 "${RESULT_DIR}/export.log"; exit 1; }
    EXPORTED_APP="${EXPORT_PATH}/${APP_NAME}.app"
    [ -d "${EXPORTED_APP}" ] || { echo "❌ Exported app not found at ${EXPORTED_APP}"; exit 1; }

    # 4. Notarize the app, then build and notarize the DMG
    if [ -n "${APPLE_ID}" ] && [ -n "${APPLE_PASSWORD}" ]; then
        echo "🔐 Notarizing app..."
        /usr/bin/ditto -c -k --keepParent "${EXPORTED_APP}" "${RESULT_DIR}/app.zip"
        notarize "${RESULT_DIR}/app.zip"
        xcrun stapler staple "${EXPORTED_APP}"
        rm -f "${RESULT_DIR}/app.zip"
    fi

    echo "💿 Creating DMG..."
    DMG_DIR="${RESULT_DIR}/dmg"
    mkdir -p "${DMG_DIR}"
    cp -R "${EXPORTED_APP}" "${DMG_DIR}/"
    ln -s /Applications "${DMG_DIR}/Applications"
    hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_DIR}" -ov -format UDZO "${DMG_PATH}" > /dev/null
    rm -rf "${DMG_DIR}"

    if [ -n "${APPLE_ID}" ] && [ -n "${APPLE_PASSWORD}" ]; then
        echo "🔐 Notarizing DMG..."
        notarize "${DMG_PATH}"
        xcrun stapler staple "${DMG_PATH}"
        xcrun stapler validate "${DMG_PATH}"
        spctl --assess --type execute --verbose "${EXPORTED_APP}"
        NOTARIZED=true
        echo "✅ Notarized and accepted by Gatekeeper."
    else
        echo "⚠️ Notarization skipped: set APPLE_ID and APPLE_PASSWORD so the DMG opens on other Macs."
    fi
    echo "✅ DMG ready: ${DMG_PATH}"

    # 5. Sparkle appcast, served from the repo root by GitHub Pages (SUFeedURL in Info.plist).
    #    Signed with the EdDSA key in the login keychain, shared with the other ct106 apps.
    SPARKLE_BIN="./Sparkle/bin"
    if [ ! -x "${SPARKLE_BIN}/generate_appcast" ]; then
        echo "⬇️ Downloading Sparkle tools..."
        SPARKLE_URL=$(curl -s https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
            | grep "browser_download_url" | grep "tar.xz" | head -n 1 | cut -d '"' -f 4)
        [ -n "${SPARKLE_URL}" ] || { echo "❌ Could not find the Sparkle download."; exit 1; }
        SPARKLE_TMP=$(mktemp -d)
        curl -sL "${SPARKLE_URL}" | tar -xJ -C "${SPARKLE_TMP}"
        mkdir -p Sparkle
        cp -R "${SPARKLE_TMP}/bin" Sparkle/
    fi
    echo "📡 Generating appcast.xml..."
    "${SPARKLE_BIN}/generate_appcast" -o appcast.xml \
        --download-url-prefix "https://github.com/chentao1006/NotiForward/releases/download/v${NEW_VERSION}/" \
        "${RESULT_DIR}"
    # generate_appcast silently leaves out the EdDSA signature (which Sparkle requires) when the
    # app lacks SUPublicEDKey or the keychain key is unavailable, so check for it.
    if ! grep -A12 "<sparkle:version>${NEW_BUILD}</sparkle:version>" appcast.xml | grep -q "edSignature"; then
        echo "❌ appcast.xml has no EdDSA signature for build ${NEW_BUILD}; Sparkle would reject the update."
        exit 1
    fi
fi

# 6. Mac App Store upload
if [ "${APP_STORE}" = "true" ]; then
    APP_STORE_ARCHIVE="${RESULT_DIR}/NotiForwardAppStore.xcarchive"
    mkdir -p "${RESULT_DIR}"
    echo "🛍️ Archiving the App Store build..."
    xcodebuild archive -project "${PROJECT}" -scheme NotiForwardAppStore -configuration Release \
        -destination "generic/platform=macOS" -archivePath "${APP_STORE_ARCHIVE}" \
        > "${RESULT_DIR}/appstore-archive.log" 2>&1 \
        || { tail -40 "${RESULT_DIR}/appstore-archive.log"; exit 1; }
    echo "📤 Uploading to App Store Connect..."
    xcodebuild -exportArchive -archivePath "${APP_STORE_ARCHIVE}" \
        -exportOptionsPlist ExportOptionsAppStore.plist -exportPath "${RESULT_DIR}/appstore" \
        -allowProvisioningUpdates > "${RESULT_DIR}/appstore-upload.log" 2>&1 \
        || { tail -40 "${RESULT_DIR}/appstore-upload.log"; exit 1; }
    echo "✅ Uploaded ${NEW_VERSION} (Build ${NEW_BUILD}). Submit it for review in App Store Connect."
fi

[ "${PUBLISH}" = "true" ] || { echo "🎉 Done (not published)."; exit 0; }

if [ "${NOTARIZED}" != "true" ] && [ "${ALLOW_UNNOTARIZED:-0}" != "1" ]; then
    echo "❌ Refusing to publish an un-notarized DMG: Gatekeeper would block it for users."
    echo "   Set APPLE_ID and APPLE_PASSWORD, or ALLOW_UNNOTARIZED=1 to publish anyway."
    exit 1
fi

# 7. Commit, tag and push
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "⚠️ Not a git repository; skipping commit, tag and GitHub release."
    exit 0
fi
TAG="v${NEW_VERSION}"
git add -A
git diff --cached --quiet || git commit -m "chore: release version ${NEW_VERSION} build ${NEW_BUILD}"
git tag -f -a "${TAG}" -m "Release ${TAG}"
BRANCH=$(git symbolic-ref --short HEAD)
git push origin "${BRANCH}"
git push -f origin "${TAG}"

# 8. GitHub release
if command -v gh >/dev/null 2>&1; then
    echo "📡 Publishing GitHub release ${TAG}..."
    gh release delete "${TAG}" --yes 2>/dev/null || true
    gh release create "${TAG}" "${DMG_PATH}" \
        --title "${APP_NAME} ${NEW_VERSION}" \
        --notes "Release ${NEW_VERSION} (Build ${NEW_BUILD})"
    echo "🎉 GitHub release completed!"
    if [ "${SKIP_HOMEBREW_RELEASE:-0}" = "1" ]; then
        echo "⏭️ Skipping Homebrew because SKIP_HOMEBREW_RELEASE=1."
    else
        echo "🍺 Updating Homebrew cask..."
        ./release-to-brew.sh "${DMG_PATH}" "${NEW_VERSION}"
        echo "🍺 Install with: brew install --cask chentao1006/tap/notiforward"
    fi
else
    echo "⚠️ GitHub CLI (gh) not found. Upload ${DMG_PATH} to the ${TAG} release manually."
fi

exit
}
