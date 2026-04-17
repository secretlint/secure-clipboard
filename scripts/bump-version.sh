#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: bump-version.sh <version> (e.g. 1.1.0)}"

# Update AppVersion.swift
sed -i '' "s/static let current = \".*\"/static let current = \"${VERSION}\"/" SecureClipboard/AppVersion.swift

# Update Info.plist version in build-app.sh
sed -i '' "s/<string>[0-9]*\.[0-9]*\.[0-9]*<\/string>/<string>${VERSION}<\/string>/" scripts/build-app.sh

echo "Updated version to ${VERSION}"
echo "  - SecureClipboard/AppVersion.swift"
echo "  - scripts/build-app.sh"
