#!/bin/sh
set -e
# App Store Connect requires TierTap.app/Watch/<name>.app (not PlugIns).
HOST="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
DEST="${HOST}/Watch"
if [ "${PLATFORM_NAME}" != "iphoneos" ]; then
  # Keep simulator installs valid: remove any placeholder/stale Watch payload.
  rm -rf "${DEST}"
  exit 0
fi
PRODUCTS_ROOT="$(dirname "${CONFIGURATION_BUILD_DIR}")"
WATCH_SRC="${PRODUCTS_ROOT}/${CONFIGURATION}-watchos/TierTap Watch App.app"
if [ ! -d "${WATCH_SRC}" ]; then
  echo "error: Watch app not found at ${WATCH_SRC}" >&2
  exit 1
fi
mkdir -p "${DEST}"
rm -rf "${DEST}/TierTap Watch App.app"
ditto "${WATCH_SRC}" "${DEST}/TierTap Watch App.app"

