#!/bin/bash
# Builds Dextra Commander, signs it with a certificate of the Dextra Commander team and packages it as ZIP and DMG.
#
# Usage: ./build_signed.sh [output directory]
#
# The signing certificate is picked automatically from the login keychain: a "Developer ID Application"
# certificate of the team is preferred, otherwise an "Apple Development" one is used.
# Builds signed with "Apple Development" run on your own Macs, but Gatekeeper rejects them on other Macs
# until they are signed with Developer ID and notarized.
#
# Environment variables:
#   DC_TEAM_ID           - the team whose certificate to use, the privileged helper only trusts this team
#   DC_SIGNING_IDENTITY  - use this signing identity (SHA-1 hash or name) instead of picking one automatically

set -e
set -o pipefail

TEAM_ID="${DC_TEAM_ID:-727BX8WD25}"

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR=$(cd "$SCRIPTS_DIR/.." && pwd)
OUTPUT_DIR=$(cd "${1:-$SCRIPTS_DIR}" && pwd)
BUILD_DIR="${SCRIPTS_DIR}/build_signed.tmp"
XCODEPROJ="${ROOT_DIR}/Source/DextraCommander/DextraCommander.xcodeproj"
ENTITLEMENTS="${ROOT_DIR}/Source/DextraCommander/DextraCommander/Resources/DextraCommander-NonMAS.entitlements"
PBUDDY=/usr/libexec/PlistBuddy

# Prints the SHA-1 hash of a valid signing identity with the specified certificate kind that belongs to the team.
find_identity() {
    local kind="$1"
    security find-identity -v -p codesigning | grep "\"${kind}: " | awk '{print $2}' | while read -r hash; do
        local subject
        subject=$(security find-certificate -a -Z -p -c "${kind}" |
                  awk -v h="${hash}" '/^SHA-1 hash:/ {take = ($3 == h)} take && /BEGIN CERTIFICATE/,/END CERTIFICATE/' |
                  openssl x509 -noout -subject 2>/dev/null || true)
        if [[ "${subject}" == *"OU=${TEAM_ID}"* || "${subject}" == *"OU = ${TEAM_ID}"* ]]; then
            echo "${hash}"
            return
        fi
    done
}

IDENTITY="${DC_SIGNING_IDENTITY:-}"
if [ -z "${IDENTITY}" ]; then
    IDENTITY=$(find_identity "Developer ID Application" || true)
fi
if [ -z "${IDENTITY}" ]; then
    IDENTITY=$(find_identity "Apple Development" || true)
fi
if [ -z "${IDENTITY}" ]; then
    echo "No signing certificate of the team ${TEAM_ID} was found in the keychain, aborting."
    echo "Create one in Xcode > Settings > Accounts > Manage Certificates, or set DC_SIGNING_IDENTITY."
    exit 1
fi
echo "Signing with: $(security find-identity -v -p codesigning | grep "${IDENTITY}" | sed -E 's/^ *[0-9]+\) [0-9A-F]+ //')"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Refresh Help.pdf if the tools to build it are available, otherwise keep the existing one.
if [ -x "$(command -v pandoc)" ] && [ -x "$(command -v xelatex)" ]; then
    (cd "${SCRIPTS_DIR}" && ./build_help.sh) # the script expects to be run from its own directory
    cp -f "${SCRIPTS_DIR}/build_help.tmp/Help.pdf" "${ROOT_DIR}/Source/DextraCommander/DextraCommander/Resources/Help.pdf"
else
    echo "pandoc or xelatex is not found, keeping the existing Help.pdf."
fi

# Build without signing - the bundle gets signed below, from the inside out.
echo "Building..."
xcodebuild \
 -project "${XCODEPROJ}" \
 -scheme DextraCommander-NonMAS \
 -configuration Release \
 CODE_SIGNING_ALLOWED=NO \
 CODE_SIGN_IDENTITY= \
 PROVISIONING_PROFILE_SPECIFIER= \
 CODE_SIGN_ENTITLEMENTS= \
 SYMROOT="${BUILD_DIR}" \
 OBJROOT="${BUILD_DIR}" \
 -parallelizeTargets \
 build > "${BUILD_DIR}/xcodebuild.log" 2>&1 || { tail -30 "${BUILD_DIR}/xcodebuild.log"; exit 1; }

# Help.pdf is tracked as an empty placeholder - put it back once it was built into the app.
git -C "${ROOT_DIR}" checkout -- Source/DextraCommander/DextraCommander/Resources/Help.pdf 2>/dev/null || true

APP_PATH=$(find "${BUILD_DIR}" -maxdepth 2 -name "Dextra Commander.app" -type d | head -1)
if [ -z "${APP_PATH}" ]; then
    echo "The built application was not found, aborting."
    exit 1
fi

echo "Signing..."
sign() {
    codesign --force --timestamp=none --options runtime --sign "${IDENTITY}" "$@"
}
SPARKLE="${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "${SPARKLE}/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "${SPARKLE}/XPCServices/Downloader.xpc"
sign "${SPARKLE}/Autoupdate"
sign "${SPARKLE}/Updater.app"
sign "${APP_PATH}/Contents/Frameworks/Sparkle.framework"
sign "${APP_PATH}/Contents/Frameworks/LetsMove.framework"
# The highlighter parses untrusted text, so it must keep running in its sandbox.
sign --entitlements "${ROOT_DIR}/Source/Viewer/resources/Highlighter.entitlements" "${APP_PATH}/Contents/XPCServices/Highlighter.xpc"
sign --identifier com.irkhin.DextraCommander.PrivilegedIOHelperV2 \
     "${APP_PATH}/Contents/Library/LaunchServices/com.irkhin.DextraCommander.PrivilegedIOHelperV2"
sign --entitlements "${ENTITLEMENTS}" "${APP_PATH}"

codesign --verify --deep --strict "${APP_PATH}"
echo "The signature is valid."

VERSION=$( ${PBUDDY} -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" )
BUILD=$( ${PBUDDY} -c "Print CFBundleVersion" "${APP_PATH}/Contents/Info.plist" )
NAME="dextra-commander-${VERSION}(${BUILD})"

# ZIP with the app, the license and where to get the source code - GPL requires both to accompany the binary.
# ditto preserves the signature and the extended attributes.
PACKAGE_DIR="${BUILD_DIR}/package/Dextra Commander ${VERSION}"
mkdir -p "${PACKAGE_DIR}"
cp -R "${APP_PATH}" "${PACKAGE_DIR}/"
cp "${ROOT_DIR}/LICENSE.md" "${PACKAGE_DIR}/LICENSE.md"
cat > "${PACKAGE_DIR}/Source code.txt" <<SOURCE
Dextra Commander ${VERSION} (${BUILD}) is free software distributed under the GNU General Public License version 3,
see LICENSE.md. The complete source code of this version is available at:
https://github.com/ai-informatics/dextra-commander/tree/v${VERSION}
SOURCE
# The app isn't notarized yet, so macOS needs the user's confirmation when it's opened for the first time.
cp "${SCRIPTS_DIR}/dmg/First Launch.pdf" "${PACKAGE_DIR}/First Launch.pdf"
ZIP_PATH="${OUTPUT_DIR}/${NAME}.zip"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${PACKAGE_DIR}" "${ZIP_PATH}"
echo "Created ${ZIP_PATH}"

# DMG with a link to /Applications. It's optional: hdiutil isn't available in some restricted environments.
STAGE_DIR="${BUILD_DIR}/dmg"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_PATH}" "${STAGE_DIR}/"
cp "${PACKAGE_DIR}/LICENSE.md" "${PACKAGE_DIR}/Source code.txt" "${PACKAGE_DIR}/First Launch.pdf" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"
DMG_PATH="${OUTPUT_DIR}/${NAME}.dmg"
rm -f "${DMG_PATH}"
if hdiutil create -volname "Dextra Commander" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}" > /dev/null 2>&1; then
    codesign --force --sign "${IDENTITY}" "${DMG_PATH}"
    echo "Created ${DMG_PATH}"
else
    echo "Could not create a DMG here, use the ZIP instead."
fi

rm -rf "${BUILD_DIR}"
