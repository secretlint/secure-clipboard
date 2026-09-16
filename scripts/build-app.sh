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

# Xcode 27 (Swift Build) emits a macOS-style resource bundle:
#   <bundle>/Contents/Info.plist
#   <bundle>/Contents/Resources/Resources/<resources>
# Bundle.module and String(localized:bundle:) need the flat layout SwiftPM's
# index build produces, with resources directly under <bundle>/Resources.
# Only transform bundles that actually have the Xcode 27 structure; leave
# already-flat bundles (e.g. older SwiftPM) untouched.
flatten_resource_bundle() {
    local bundle="$1"
    [ -d "${bundle}/Contents/Resources/Resources" ] || return 0
    [ -f "${bundle}/Contents/Info.plist" ] || return 0
    mv "${bundle}/Contents/Resources/Resources" "${bundle}/Resources"
    mv "${bundle}/Contents/Info.plist" "${bundle}/Info.plist"
    rm -rf "${bundle}/Contents"
}

# Copy SPM resource bundle where Bundle.module expects it.
# Xcode 27 (Swift Build) checks Bundle.main.resourceURL first: Contents/Resources/.
cp -R ".build/release/${APP_NAME}_${APP_NAME}.bundle" "${RESOURCES}/"
flatten_resource_bundle "${RESOURCES}/${APP_NAME}_${APP_NAME}.bundle"
# Older SwiftPM accessors (Xcode <= 16.x, used by the release CI) check the .app root only.
cp -R ".build/release/${APP_NAME}_${APP_NAME}.bundle" "${APP_DIR}/"
flatten_resource_bundle "${APP_DIR}/${APP_NAME}_${APP_NAME}.bundle"

# Copy CLI binary and create symlinks for secure-pbpaste/secure-pbcopy
cp ".build/release/SecureClipboardCLI" "${MACOS}/SecureClipboardCLI"
ln -sf SecureClipboardCLI "${MACOS}/secure-pbpaste"
ln -sf SecureClipboardCLI "${MACOS}/secure-pbcopy"

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
    <string>1.9.0</string>
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
