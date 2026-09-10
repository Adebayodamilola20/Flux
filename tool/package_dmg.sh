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
#   appcast.xml              the Sparkle feed this build's app reads
#   latest.json              the feed the *old* Flutter app read
#
# All three go on the GitHub release named by TAG (default v<version>),
# replacing what is there, so `releases/latest/download/…` always resolves to
# the newest without any of them needing a new URL.
#
# Two feeds, because there are two generations of the app in the wild. The
# current one uses Sparkle, which reads appcast.xml, verifies the EdDSA
# signature and installs in the background. Copies still running the Flutter
# build poll latest.json and can only offer a download — that generation has
# no installer. Dropping latest.json would stop those copies ever hearing
# about another release, so it is still written.
#
# Both carry the same build stamp: the minute this script ran, UTC, as
# yyyyMMddHHmm. It rises with every build, which is what makes "is this newer"
# answerable without touching the marketing version.
#
# Usage:  tool/package_dmg.sh ["what changed, one line"]
set -euo pipefail

APP_NAME="DevNotch"
# The single source of truth for the version is project.yml, which is also what
# stamps Info.plist. Reading it here keeps the DMG's name and the manifest from
# drifting away from the bundle they describe.
VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
TAG="${TAG:-v${VERSION}}"
REPO="${REPO:-Adebayodamilola20/Flux}"
NOTES="${1:-}"
BUILD_STAMP="$(date -u +%Y%m%d%H%M)"

DERIVED="build/xcode"
BUILT="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
DIST="build/dist"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
MANIFEST="${DIST}/latest.json"
APPCAST="${DIST}/appcast.xml"
STAGE="build/dmg-stage"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31mstopped: %s\033[0m\n' "$1" >&2; exit 1; }

command -v gh >/dev/null || fail "the gh CLI is needed to publish"

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${APP_NAME}-${VERSION}.dmg"
command -v xcodegen >/dev/null || fail "xcodegen is needed: brew install xcodegen"

step "Generating the Xcode project"
xcodegen generate >/dev/null

step "Building ${APP_NAME} ${VERSION} (build ${BUILD_STAMP})"
rm -rf "${BUILT}"
# Signing is switched off for the build itself and applied afterwards. The
# project asks for a Developer ID identity, which this machine does not have;
# overriding it here keeps project.yml honest about what a real release wants.
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  CURRENT_PROJECT_VERSION="${BUILD_STAMP}" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

[[ -d "${BUILT}" ]] || fail "the build produced no app at ${BUILT}"

# Ad-hoc signed, inside out, so the bundle passes its own seal. An app that
# fails a strict verify can be reported as damaged on another Mac, on top of
# the Gatekeeper warning the missing Developer ID already causes.
step "Signing (ad-hoc)"
codesign --force --deep --sign - "${BUILT}"
codesign --verify --deep --strict "${BUILT}" || fail "the app does not verify"

step "Building the disk image"
rm -rf "${STAGE}" && mkdir -p "${STAGE}" "${DIST}"
cp -R "${BUILT}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE}" \
  -ov -format UDZO "${DMG}" >/dev/null

# --- the update feed --------------------------------------------------------
# Signed with our own EdDSA key, whose private half lives in this machine's
# login keychain. Sparkle refuses an update whose signature does not verify,
# so a wrongly signed image simply never installs, which is the failure worth
# having. Nothing to do with Apple's Developer ID: that one decides whether
# Gatekeeper opens the download at all, this one decides whether Sparkle
# trusts it as an update.
step "Signing the update"
SIGN_TOOL="${DERIVED}/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "${SIGN_TOOL}" ]] || fail "Sparkle's sign_update is missing at ${SIGN_TOOL}"

SIGNATURE_LINE="$("${SIGN_TOOL}" "${DMG}")" || fail "could not sign the disk image.
  The private key lives in this machine's login keychain; if it is gone, make a
  new pair with Sparkle's generate_keys and put the public half in project.yml."
echo "${SIGNATURE_LINE}"

step "Writing the appcast"
python3 tool/make_appcast.py \
  "${VERSION}" "${BUILD_STAMP}" "${DOWNLOAD_URL}" "${NOTES}" "${SIGNATURE_LINE}" "${APPCAST}"
cat "${APPCAST}"

step "Writing the manifest"
python3 - "$VERSION" "$BUILD_STAMP" "$DOWNLOAD_URL" "$NOTES" "$MANIFEST" <<'PY'
import json, sys
version, build, url, notes, out = sys.argv[1:]
with open(out, "w") as f:
    json.dump({"version": version, "build": build, "url": url, "notes": notes}, f, indent=2)
    f.write("\n")
PY
cat "${MANIFEST}"

step "Publishing to ${REPO} ${TAG}"
gh release upload "${TAG}" "${DMG}" "${MANIFEST}" "${APPCAST}" --clobber --repo "${REPO}"

step "Verifying the live download"
SCRATCH="$(mktemp -d)"
curl -sL --max-time 300 -o "${SCRATCH}/live.dmg" "${DOWNLOAD_URL}?t=$(date +%s)"
LOCAL="$(shasum -a 256 "${DMG}" | cut -d' ' -f1)"
LIVE="$(shasum -a 256 "${SCRATCH}/live.dmg" | cut -d' ' -f1)"
rm -rf "${SCRATCH}"
[[ "${LOCAL}" == "${LIVE}" ]] || fail "the live download does not match the local image yet (CDN lag); re-run the check in a minute"

printf '\n\033[32mdone: %s (build %s)\033[0m\n' "${DMG}" "${BUILD_STAMP}"
echo "Installed copies will see this build on their next update check."
