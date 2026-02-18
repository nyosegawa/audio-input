#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioInput"
APP_DIR="$PROJECT_DIR/build/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Building whisper.cpp dependency ==="
"$PROJECT_DIR/scripts/build-whisper-lib.sh"

echo "=== Building $APP_NAME ==="
cd "$PROJECT_DIR"
swift build -c release 2>&1

echo "=== Creating app bundle ==="
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy .env file if exists
if [ -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env" "$MACOS_DIR/.env"
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AudioInput</string>
    <key>CFBundleIdentifier</key>
    <string>com.nyosegawa.audio-input</string>
    <key>CFBundleName</key>
    <string>AudioInput</string>
    <key>CFBundleDisplayName</key>
    <string>AudioInput</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>AudioInputは音声入力のためにマイクを使用します。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>AudioInputはテキスト挿入のためにアクセシビリティ機能を使用します。</string>
</dict>
</plist>
PLIST

# Ad-hoc sign the binary so macOS recognizes it consistently
# for accessibility/input monitoring permissions across rebuilds
codesign --force --sign - --identifier "com.nyosegawa.audio-input" "$MACOS_DIR/$APP_NAME"

# Reset TCC accessibility entry so macOS re-prompts for the new binary
tccutil reset Accessibility com.nyosegawa.audio-input 2>/dev/null || true

echo "=== App bundle created at: $APP_DIR ==="
echo "Run with: open $APP_DIR"
