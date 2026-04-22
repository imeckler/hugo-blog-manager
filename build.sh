#!/usr/bin/env bash
# Builds BlogManager as a macOS .app bundle in ./build/BlogManager.app
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BlogManager"
APP_DISPLAY="Blog Manager"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_DISPLAY}.app"
CONFIG="${CONFIG:-release}"

echo "==> swift build --configuration ${CONFIG}"
swift build --configuration "${CONFIG}"

BIN_PATH="$(swift build --configuration "${CONFIG}" --show-bin-path)"
EXE="${BIN_PATH}/${APP_NAME}"

if [[ ! -x "${EXE}" ]]; then
    echo "error: built executable not found at ${EXE}" >&2
    exit 1
fi

echo "==> packaging ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${EXE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper allows running locally.
codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo "Done. Run: open '${APP_BUNDLE}'"
