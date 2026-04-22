#!/usr/bin/env bash
# Usage: ./release.sh <version> [release notes...]
# Example: ./release.sh v0.1 "First cut"
#
# Builds the .app, zips it, tags, pushes, and creates a GitHub release.
set -euo pipefail

cd "$(dirname "$0")"

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <version> [release notes...]" >&2
    echo "example: $0 v0.1 \"First build\"" >&2
    exit 2
fi

VERSION="$1"
shift || true
NOTES="${*:-Release $VERSION}"

if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh CLI not found. Install with: brew install gh" >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "error: gh not authenticated. Run: gh auth login" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree has uncommitted changes. Commit or stash first." >&2
    git status --short >&2
    exit 1
fi

if git rev-parse --verify --quiet "refs/tags/${VERSION}" >/dev/null; then
    echo "error: tag ${VERSION} already exists locally" >&2
    exit 1
fi

if gh release view "${VERSION}" >/dev/null 2>&1; then
    echo "error: release ${VERSION} already exists on GitHub" >&2
    exit 1
fi

echo "==> building release .app"
./build.sh

APP_PATH="build/Blog Manager.app"
ZIP_NAME="BlogManager-${VERSION}-macos.zip"
ZIP_PATH="build/${ZIP_NAME}"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "error: ${APP_PATH} not found after build" >&2
    exit 1
fi

echo "==> zipping to ${ZIP_PATH}"
rm -f "${ZIP_PATH}"
# ditto preserves macOS metadata (extended attrs, codesign) better than /usr/bin/zip
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> tagging ${VERSION}"
git tag -a "${VERSION}" -m "${NOTES}"
git push origin "${VERSION}"

echo "==> creating GitHub release"
gh release create "${VERSION}" \
    "${ZIP_PATH}" \
    --title "${VERSION}" \
    --notes "${NOTES}"

echo
echo "Done. Release URL:"
gh release view "${VERSION}" --json url -q .url
