#!/usr/bin/env bash
#
# Builds, packages and publishes the ad-hoc signed DevNotch disk image, and the
# manifest the app checks for updates.
#
# This is the path used while there is no Developer ID certificate. It does
# everything tool/release.sh does except sign with an identity and notarise —
# which means the download still needs Privacy & Security → Open Anyway on
# first launch. When the certificate arrives, use tool/release.sh instead.
#
# WHAT GETS PUBLISHED
#
#   DevNotch-<version>.dmg   the app
#   latest.json              { version, build, url, notes }
#
# Both go on the GitHub release named by TAG (default v<version>), replacing
# what is there. The app fetches latest.json from the "latest" release URL,
# compares `build` — the minute this script ran, UTC, yyyyMMddHHmm — against
# the stamp compiled into it, and offers the download when the published one
# is newer. The marketing version is not compared, so the asset can be
# replaced in place as many times as needed without bumping it.
#
# Usage:  tool/package_dmg.sh ["what changed, one line"]
set -euo pipefail

APP_NAME="DevNotch"
VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d+ -f1)"
TAG="${TAG:-v${VERSION}}"
REPO="${REPO:-Adebayodamilola20/Flux}"
NOTES="${1:-}"
BUILD_STAMP="$(date -u +%Y%m%d%H%M)"

BUILT="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST="build/dist"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
MANIFEST="${DIST}/latest.json"
STAGE="build/dmg-stage"
ENTITLEMENTS="macos/Runner/Release.entitlements"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31mstopped: %s\033[0m\n' "$1" >&2; exit 1; }

command -v gh >/dev/null || fail "the gh CLI is needed to publish"
[[ -f "${ENTITLEMENTS}" ]] || fail "missing ${ENTITLEMENTS}"

step "Building ${APP_NAME} ${VERSION} (build ${BUILD_STAMP})"
rm -rf "${BUILT}"
flutter build macos --release \
  --dart-define=APP_VERSION="${VERSION}" \
  --dart-define=BUILD_STAMP="${BUILD_STAMP}"
[[ -d "${BUILT}" ]] || fail "the build produced no app at ${BUILT}"

# Flutter's build leaves App.framework failing the bundle's own seal, which a
# strict verify reports as "nested code is modified". Re-signing the whole
# bundle inside-out makes it verify; still ad-hoc, still the same warning on
# first launch, but no "damaged" dialog.
step "Re-signing (ad-hoc)"
codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${BUILT}"
codesign --verify --deep --strict "${BUILT}" || fail "the app does not verify"

step "Building the disk image"
rm -rf "${STAGE}" && mkdir -p "${STAGE}" "${DIST}"
cp -R "${BUILT}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE}" \
  -ov -format UDZO "${DMG}" >/dev/null

step "Writing the manifest"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}.dmg"
python3 - "$VERSION" "$BUILD_STAMP" "$DOWNLOAD_URL" "$NOTES" "$MANIFEST" <<'PY'
import json, sys
version, build, url, notes, out = sys.argv[1:]
with open(out, "w") as f:
    json.dump({"version": version, "build": build, "url": url, "notes": notes}, f, indent=2)
    f.write("\n")
PY
cat "${MANIFEST}"

step "Publishing to ${REPO} ${TAG}"
gh release upload "${TAG}" "${DMG}" "${MANIFEST}" --clobber --repo "${REPO}"

step "Verifying the live download"
SCRATCH="$(mktemp -d)"
curl -sL --max-time 300 -o "${SCRATCH}/live.dmg" "${DOWNLOAD_URL}?t=$(date +%s)"
LOCAL="$(shasum -a 256 "${DMG}" | cut -d' ' -f1)"
LIVE="$(shasum -a 256 "${SCRATCH}/live.dmg" | cut -d' ' -f1)"
rm -rf "${SCRATCH}"
[[ "${LOCAL}" == "${LIVE}" ]] || fail "the live download does not match the local image yet (CDN lag); re-run the check in a minute"

printf '\n\033[32mdone: %s (build %s)\033[0m\n' "${DMG}" "${BUILD_STAMP}"
echo "Installed copies will see this build on their next update check."
