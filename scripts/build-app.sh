#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SecureClipboard"
BUNDLE_ID="com.secretlint.SecureClipboard"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Building ${APP_NAME}..."
swift build --disable-sandbox -c release

echo "Creating ${APP_NAME}.app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

# Copy binary
cp ".build/release/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Copy resources from the bundle
cp -R ".build/release/${APP_NAME}_${APP_NAME}.bundle/Resources/" "${RESOURCES}/"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Built: ${APP_DIR}"
echo "Run: open ${APP_DIR}"
