#!/usr/bin/env bash
#
# Builds, signs, notarises and packages DevNotch for distribution.
#
# WHY THIS EXISTS
#
# An ad-hoc signed app is refused by every Mac that downloads it. There is no
# flag, entitlement or packaging trick that changes that — Gatekeeper checks
# for a Developer ID signature and a notarisation ticket from Apple, and
# absent either one it tells the user the app may be malware. The only way to
# stop people having to visit Privacy & Security is to actually sign and
# notarise, which is what this does.
#
# WHAT YOU NEED FIRST
#
#   1. A paid Apple Developer Program membership. Apple Development
#      certificates — which this machine already has — are for running on your
#      own devices. Distribution needs a "Developer ID Application"
#      certificate, and that is only issued to paid accounts.
#
#   2. That certificate in your login keychain. Xcode →
#      Settings → Accounts → Manage Certificates → + → Developer ID
#      Application. Confirm with:
#
#          security find-identity -v -p codesigning | grep "Developer ID"
#
#   3. Notarisation credentials stored once, so this script never handles a
#      password:
#
#          xcrun notarytool store-credentials devnotch \
#            --apple-id you@example.com \
#            --team-id YOURTEAMID \
#            --password <app-specific-password>
#
#      The app-specific password comes from appleid.apple.com → Sign-In and
#      Security → App-Specific Passwords. It is not your Apple ID password.
#
# Then: tool/release.sh
set -euo pipefail

APP_NAME="DevNotch"
VERSION="$(grep '^version:' pubspec.yaml | sed 's/version: *//' | cut -d+ -f1)"
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-devnotch}"
BUILT="build/macos/Build/Products/Release/${APP_NAME}.app"
DIST="build/dist"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"
STAGE="build/dmg-stage"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31mstopped: %s\033[0m\n' "$1" >&2; exit 1; }

# --- credentials, checked before anything slow runs ------------------------
step "Checking credentials"

IDENTITY="$(security find-identity -v -p codesigning \
  | grep 'Developer ID Application' \
  | head -1 \
  | sed 's/.*"\(.*\)"/\1/')" || true

if [[ -z "${IDENTITY}" ]]; then
  fail "no 'Developer ID Application' certificate in the keychain.
  This machine has Apple Development certificates, which cannot sign for
  distribution. See the notes at the top of this script."
fi
echo "signing identity: ${IDENTITY}"

if ! xcrun notarytool history --keychain-profile "${KEYCHAIN_PROFILE}" >/dev/null 2>&1; then
  fail "no stored notarisation profile called '${KEYCHAIN_PROFILE}'.
  Run the store-credentials command in the notes at the top of this script,
  or set NOTARY_PROFILE to the name you used."
fi
echo "notary profile:   ${KEYCHAIN_PROFILE}"

# --- build -----------------------------------------------------------------
BUILD_STAMP="$(date -u +%Y%m%d%H%M)"
step "Building ${APP_NAME} ${VERSION} (build ${BUILD_STAMP})"
rm -rf "${BUILT}"
# The stamp is what installed copies compare against latest.json; see
# tool/package_dmg.sh, which publishes that manifest.
flutter build macos --release \
  --dart-define=APP_VERSION="${VERSION}" \
  --dart-define=BUILD_STAMP="${BUILD_STAMP}"

[[ -d "${BUILT}" ]] || fail "the build produced no app at ${BUILT}"

# --- sign ------------------------------------------------------------------
# Inside out: nested code has to be signed before the bundle that contains it,
# or the outer signature is computed over parts that then change.
#
# --options runtime turns on the hardened runtime, which notarisation
# requires. --timestamp records a trusted timestamp so the signature stays
# valid after the certificate expires.
step "Signing"
find "${BUILT}/Contents/Frameworks" -type f -perm -u+x -print0 2>/dev/null \
  | while IFS= read -r -d '' bin; do
      codesign --force --timestamp --options runtime \
        --sign "${IDENTITY}" "${bin}"
    done

find "${BUILT}/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 2>/dev/null \
  | while IFS= read -r -d '' fw; do
      codesign --force --timestamp --options runtime \
        --sign "${IDENTITY}" "${fw}"
    done

# The entitlements the app actually relies on: the sandbox is off so it can
# read the Keychain items and session files other tools own, and spawn the
# CLIs it reads. Signed with the same list the build used.
ENTITLEMENTS="macos/Runner/Release.entitlements"
[[ -f "${ENTITLEMENTS}" ]] || fail "missing ${ENTITLEMENTS}"

codesign --force --timestamp --options runtime \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${IDENTITY}" "${BUILT}"

codesign --verify --deep --strict --verbose=2 "${BUILT}"

# --- package ---------------------------------------------------------------
step "Building the disk image"
rm -rf "${STAGE}" && mkdir -p "${STAGE}" "${DIST}"
cp -R "${BUILT}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGE}" \
  -ov -format UDZO "${DMG}" >/dev/null

# The disk image is signed too. An unsigned image around a signed app still
# trips the download warning.
codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"

# --- notarise --------------------------------------------------------------
# Apple scans the image and issues a ticket. --wait blocks until the verdict,
# which is usually a couple of minutes.
step "Notarising (this waits on Apple)"
xcrun notarytool submit "${DMG}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" \
  --wait

# Stapling attaches the ticket to the image, so a Mac with no network still
# sees it as notarised.
step "Stapling the ticket"
xcrun stapler staple "${DMG}"

# --- prove it --------------------------------------------------------------
# The check that matters. `spctl` answers the question Gatekeeper will ask on
# someone else's Mac, so a pass here is the thing that means no warning.
step "Verifying as Gatekeeper will"
spctl --assess --type open --context context:primary-signature -vv "${DMG}"
xcrun stapler validate "${DMG}"

printf '\n\033[32mdone: %s\033[0m\n' "${DMG}"
echo "Signed, notarised and stapled. This one opens on a double-click."
