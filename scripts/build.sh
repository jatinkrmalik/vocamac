#!/bin/bash
# build.sh — Build, bundle, and sign VocaMac
# Usage: ./scripts/build.sh [debug|release]
#
# This script:
# 1. Builds VocaMac with Swift Package Manager
# 2. Creates/updates the .app bundle
# 3. Ad-hoc code signs with a stable identifier + entitlements
#
# IMPORTANT: After the first build, grant Accessibility and Input Monitoring
# permissions to VocaMac.app. These permissions persist as long as you don't
# delete the app bundle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

CONFIG="${1:-release}"
BUNDLE_ID="com.vocamac.app"
APP_NAME="VocaMac"
APP_DIR="${APP_NAME}.app"
ENTITLEMENTS="VocaMac.entitlements"

# Kill any running VocaMac instances before building
if pgrep -f "VocaMac" > /dev/null 2>&1; then
    echo "🛑 Stopping running VocaMac..."
    pkill -f "VocaMac" 2>/dev/null
    sleep 1
fi

echo "🔨 Building VocaMac ($CONFIG)..."
swift build -c "$CONFIG"

# Find the built binary
BINARY=".build/arm64-apple-macosx/${CONFIG}/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed — binary not found at $BINARY"
    exit 1
fi

# Check if this is a fresh bundle creation or an update
FIRST_TIME=false
if [ ! -d "${APP_DIR}" ]; then
    FIRST_TIME=true
fi

echo "📦 Updating app bundle..."

# Create bundle structure
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Update binary
cp -f "$BINARY" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Update resource bundles
find ".build/arm64-apple-macosx/${CONFIG}" -maxdepth 1 -name "*.bundle" | while read -r bundle; do
    cp -rf "$bundle" "${APP_DIR}/Contents/Resources/"
done

# Copy app icon
if [ -f "Sources/VocaMac/Resources/AppIcon.icns" ]; then
    cp -f "Sources/VocaMac/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
    echo "📎 App icon copied"
fi

# Create/update Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << EOF
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
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>VocaMac needs microphone access to capture your voice for transcription.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "🔏 Code signing (${BUNDLE_ID})..."

# Sign nested bundles first
find "${APP_DIR}/Contents/Resources" -name "*.bundle" -exec \
    codesign --force --sign - {} \; 2>/dev/null || true

# Sign the main app
codesign --force --sign - \
    --identifier "$BUNDLE_ID" \
    --entitlements "$ENTITLEMENTS" \
    "${APP_DIR}"

echo "✅ Build complete!"
echo ""
echo "   App: $(pwd)/${APP_DIR}"
echo ""

# Verify
codesign -dv "${APP_DIR}" 2>&1 | grep -E "Identifier|CDHash"

echo ""
echo "🚀 To run:  open ${APP_DIR}"
echo "🔄 To rebuild: ./scripts/build.sh"

if [ "$FIRST_TIME" = true ]; then
    echo ""
    echo "⚠️  FIRST TIME SETUP:"
    echo "   1. Run: open ${APP_DIR}"
    echo "   2. System Settings → Privacy & Security → Accessibility → add VocaMac.app → ON"
    echo "   3. System Settings → Privacy & Security → Input Monitoring → add VocaMac.app → ON"
    echo "   4. Restart VocaMac: killall VocaMac && open ${APP_DIR}"
    echo ""
    echo "   ⚠️  Permissions reset on every rebuild (ad-hoc signing limitation)."
    echo "   💡 TIP: To avoid this, add your Terminal app to Accessibility & Input Monitoring"
    echo "      and run VocaMac directly: .build/arm64-apple-macosx/release/VocaMac"
fi
