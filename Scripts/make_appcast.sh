#!/bin/bash

# Writes appcast.xml - the Sparkle update feed announcing a release to the existing installations.
# The app looks for it at https://github.com/ai-informatics/dextra-commander/releases/latest/download/appcast.xml,
# so it has to be attached to the latest GitHub release.
#
# Usage: ./make_appcast.sh <version> <build> <path to the DMG> [output path]
# Example: ./make_appcast.sh 2.1.0 4353 ~/Desktop/DextraCommander-2.1.0.dmg
#
# The update is signed with the EdDSA key stored in the keychain (created with Sparkle's generate_keys);
# macOS may ask to allow sign_update to access it.

set -euo pipefail

if [ $# -lt 3 ]; then
    echo "Usage: $0 <version> <build> <path to the DMG> [output path]"
    exit 1
fi

VERSION="$1"
BUILD="$2"
DMG="$3"
SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="${SCRIPTS_DIR}/.."
OUTPUT="${4:-$(dirname "${DMG}")/appcast.xml}"
REPO_URL="https://github.com/ai-informatics/dextra-commander"
DOWNLOAD_URL="${REPO_URL}/releases/download/v${VERSION}/$(basename "${DMG}")"

[ -f "${DMG}" ] || { echo "Not found: ${DMG}"; exit 1; }

# Sparkle's command line tools of the same version as the framework inside the app.
SPARKLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "${ROOT_DIR}/3rd_Party/Sparkle/Sparkle.framework/Versions/B/Resources/Info.plist")
TOOLS_DIR="${HOME}/Library/Caches/DextraCommander/Sparkle-${SPARKLE_VERSION}"
if ! [ -x "${TOOLS_DIR}/bin/sign_update" ]; then
    echo "Downloading Sparkle ${SPARKLE_VERSION} tools..."
    mkdir -p "${TOOLS_DIR}"
    curl -sfL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
        | tar -xJ -C "${TOOLS_DIR}" ./bin
fi

# Prints e.g.: sparkle:edSignature="..." length="12345"
SIGNATURE=$("${TOOLS_DIR}/bin/sign_update" "${DMG}")

MIN_MACOS=$(grep -E '^MACOSX_DEPLOYMENT_TARGET' "${ROOT_DIR}/Source/XCConfig/common.xcconfig" | sed -E 's/.*= *//')

# The release notes from WHATS_NEW.md as simple HTML, shown by Sparkle in the update window.
NOTES=$(awk -v version="## Version ${VERSION}" 'index($0, version) == 1 { f = 1; next } /^## / { f = 0 } f' \
    "${ROOT_DIR}/WHATS_NEW.md" | python3 -c '
import html, re, sys
items = [line[2:].strip() for line in sys.stdin if line.startswith("- ")]
def convert(text):
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text, quote=False))
print("<ul>" + "".join("<li>" + convert(i) + "</li>" for i in items) + "</ul>")
')
[ "${NOTES}" != "<ul></ul>" ] || { echo "No release notes for ${VERSION} in WHATS_NEW.md"; exit 1; }

cat > "${OUTPUT}" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Dextra Commander</title>
        <link>${REPO_URL}</link>
        <description>Updates of Dextra Commander</description>
        <language>en</language>
        <item>
            <title>Dextra Commander ${VERSION}</title>
            <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_MACOS}</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>${REPO_URL}/releases/tag/v${VERSION}</sparkle:fullReleaseNotesLink>
            <description><![CDATA[${NOTES}]]></description>
            <enclosure url="${DOWNLOAD_URL}" type="application/octet-stream" ${SIGNATURE} />
        </item>
    </channel>
</rss>
APPCAST

echo "Created ${OUTPUT}"
