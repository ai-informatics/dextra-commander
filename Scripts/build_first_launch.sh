#!/bin/sh

# Builds Scripts/dmg/First Launch.pdf, the guide for opening the not yet notarized app for the first time,
# from build_first_launch.swift and the screenshots in Docs/FirstLaunch.
# The PDF is shipped with the releases by build_signed.sh and is kept in the repository,
# so this script is needed only after changing the guide.

set -e
set -o pipefail

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

swiftc -module-cache-path "${TMP_DIR}/cache" "${SCRIPTS_DIR}/build_first_launch.swift" -o "${TMP_DIR}/build_first_launch"
"${TMP_DIR}/build_first_launch" "${SCRIPTS_DIR}/../Docs/FirstLaunch" "${SCRIPTS_DIR}/dmg/First Launch.pdf"
