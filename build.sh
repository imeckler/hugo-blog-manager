#!/usr/bin/env bash
# Builds BlogManager as a macOS .app bundle in ./build/BlogManager.app
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BlogManager"
APP_DISPLAY="Blog Manager"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_DISPLAY}.app"
CONFIG="${CONFIG:-release}"
# Target Intel Macs running macOS 11.4+. Set ARCH=arm64 or ARCH=universal to
# override; "universal" builds both arches and lipos them together.
ARCH="${ARCH:-x86_64}"

swift_build() {
    local arch="$1"
    swift build \
        --configuration "${CONFIG}" \
        --triple "${arch}-apple-macosx11.0" \
        "${@:2}"
}

if [[ "${ARCH}" == "universal" ]]; then
    echo "==> swift build universal (x86_64 + arm64)"
    swift_build x86_64
    X86_EXE="$(swift_build x86_64 --show-bin-path)/${APP_NAME}"
    swift_build arm64
    ARM_EXE="$(swift_build arm64 --show-bin-path)/${APP_NAME}"
    MERGED_DIR="${BUILD_DIR}/universal"
    mkdir -p "${MERGED_DIR}"
    EXE="${MERGED_DIR}/${APP_NAME}"
    lipo -create -output "${EXE}" "${X86_EXE}" "${ARM_EXE}"
else
    echo "==> swift build ${ARCH} (macOS 11.0+)"
    swift_build "${ARCH}"
    BIN_PATH="$(swift_build "${ARCH}" --show-bin-path)"
    EXE="${BIN_PATH}/${APP_NAME}"
fi

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
