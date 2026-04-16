#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: download-secretlint.sh <version>}"

ARCH=$(uname -m)
case "$ARCH" in
  arm64)
    PLATFORM="darwin-arm64"
    ;;
  x86_64)
    PLATFORM="darwin-x64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

BINARY_NAME="secretlint-${VERSION}-${PLATFORM}"
URL="https://github.com/secretlint/secretlint/releases/download/v${VERSION}/${BINARY_NAME}"
DEST="SecureClipboard/Resources/secretlint"

echo "Downloading secretlint ${VERSION} for ${PLATFORM}..."
curl -fSL "${URL}" -o "${DEST}"

# Checksum verification
CHECKSUM_FILE="secretlint-${VERSION}-sha256sum.txt"
CHECKSUM_URL="https://github.com/secretlint/secretlint/releases/download/v${VERSION}/${CHECKSUM_FILE}"
curl -fSL "${CHECKSUM_URL}" -o "/tmp/${CHECKSUM_FILE}"
EXPECTED=$(grep "${BINARY_NAME}" "/tmp/${CHECKSUM_FILE}" | awk '{print $1}')
ACTUAL=$(shasum -a 256 "${DEST}" | awk '{print $1}')
rm -f "/tmp/${CHECKSUM_FILE}"

if [ "${EXPECTED}" != "${ACTUAL}" ]; then
    echo "Checksum verification failed!" >&2
    echo "Expected: ${EXPECTED}" >&2
    echo "Actual:   ${ACTUAL}" >&2
    rm -f "${DEST}"
    exit 1
fi
echo "Checksum verified."

chmod +x "${DEST}"
echo "Downloaded to ${DEST}"
