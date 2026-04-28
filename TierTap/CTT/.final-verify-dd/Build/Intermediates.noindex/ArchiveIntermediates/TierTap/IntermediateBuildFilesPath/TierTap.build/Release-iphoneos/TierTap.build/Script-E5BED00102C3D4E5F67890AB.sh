#!/bin/sh
set -e
# App Store Connect requires TierTap.app/Watch/<name>.app (not PlugIns).
if [ "${PLATFORM_NAME}" != "iphoneos" ]; then
  exit 0
fi
PRODUCTS_ROOT="$(dirname "${CONFIGURATION_BUILD_DIR}")"
WATCH_SRC="${PRODUCTS_ROOT}/${CONFIGURATION}-watchos/TierTap Watch App.app"
HOST="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
DEST="${HOST}/Watch"
if [ ! -d "${WATCH_SRC}" ]; then
  echo "error: Watch app not found at ${WATCH_SRC}" >&2
  exit 1
fi
mkdir -p "${DEST}"
rm -rf "${DEST}/TierTap Watch App.app"
ditto "${WATCH_SRC}" "${DEST}/TierTap Watch App.app"

