#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioInput"
APP_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
DMG_DIR="$PROJECT_DIR/build/dmg"
DMG_PATH="$PROJECT_DIR/build/${APP_NAME}.dmg"

# Version from Info.plist (set by build-app.sh)
VERSION="${VERSION:-1.0.0}"

# Build app first if not exists
if [ ! -d "$APP_DIR" ]; then
    echo "=== App bundle not found, building first ==="
    "$PROJECT_DIR/scripts/build-app.sh"
fi

echo "=== Creating DMG ==="

# Clean previous artifacts
rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"

# Copy app to staging directory
cp -R "$APP_DIR" "$DMG_DIR/"

# Create symlink to /Applications
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG using hdiutil
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

# Clean staging
rm -rf "$DMG_DIR"

# Output info
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

echo "=== DMG created ==="
echo "  Path: $DMG_PATH"
echo "  Size: $DMG_SIZE"
echo "  SHA256: $DMG_SHA256"
