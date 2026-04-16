#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: download-secretlint.sh <version>}"
PLATFORM="darwin-arm64"
BINARY_NAME="secretlint-${VERSION}-${PLATFORM}"
URL="https://github.com/secretlint/secretlint/releases/download/v${VERSION}/${BINARY_NAME}"
DEST="SecureClipboard/Resources/secretlint"

echo "Downloading secretlint ${VERSION} for ${PLATFORM}..."
curl -fSL "${URL}" -o "${DEST}"
chmod +x "${DEST}"
echo "Downloaded to ${DEST}"
