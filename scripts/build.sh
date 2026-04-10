#!/bin/bash
# build.sh — Build, bundle, and sign VocaMac
# Usage: ./scripts/build.sh [debug|release]
#
# This script:
# 1. Builds VocaMac with Swift Package Manager
# 2. Creates/updates the .app bundle
# 3. Code signs — Developer ID if CODE_SIGN_IDENTITY is set, ad-hoc otherwise
#
# Environment variables:
#   CODE_SIGN_IDENTITY  — Signing identity to use. Defaults to auto-detect
#                         Developer ID Application in the login keychain.
#                         Set to "-" to force ad-hoc signing.
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

# Resolve signing identity:
# 1. Use CODE_SIGN_IDENTITY env var if set
# 2. Auto-detect Developer ID Application in the login keychain
# 3. Fall back to ad-hoc signing (-)
if [ -z "${CODE_SIGN_IDENTITY+x}" ]; then
    DETECTED=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    if [ -n "$DETECTED" ]; then
        CODE_SIGN_IDENTITY="$DETECTED"
        echo "🔐 Auto-detected signing identity: $CODE_SIGN_IDENTITY"
    else
        CODE_SIGN_IDENTITY="-"
        echo "⚠️  No Developer ID found — using ad-hoc signing"
    fi
fi

if [ "$CODE_SIGN_IDENTITY" = "-" ]; then
    echo "🔏 Signing mode: ad-hoc (permissions reset on every rebuild)"
else
    echo "🔏 Signing mode: Developer ID"
fi

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

# Copy app icon and compile Asset Catalog
if [ -f "Sources/VocaMac/Resources/AppIcon.icns" ]; then
    cp -f "Sources/VocaMac/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

    # Extract PNGs from .icns and compile an Asset Catalog (Assets.car)
    # Modern macOS requires Assets.car for icons to render in Finder
    ICONSET_DIR="/tmp/vocamac-icon-build.iconset"
    XCASSETS_DIR="/tmp/vocamac-icon-build.xcassets"
    rm -rf "$ICONSET_DIR" "$XCASSETS_DIR"

    iconutil --convert iconset "Sources/VocaMac/Resources/AppIcon.icns" -o "$ICONSET_DIR" 2>/dev/null
    if [ -d "$ICONSET_DIR" ]; then
        mkdir -p "${XCASSETS_DIR}/AppIcon.appiconset"
        cp "$ICONSET_DIR"/*.png "${XCASSETS_DIR}/AppIcon.appiconset/"
        cat > "${XCASSETS_DIR}/AppIcon.appiconset/Contents.json" << 'ICONJSON'
{
  "images": [
    {"filename":"icon_16x16.png","idiom":"mac","scale":"1x","size":"16x16"},
    {"filename":"icon_16x16@2x.png","idiom":"mac","scale":"2x","size":"16x16"},
    {"filename":"icon_32x32.png","idiom":"mac","scale":"1x","size":"32x32"},
    {"filename":"icon_32x32@2x.png","idiom":"mac","scale":"2x","size":"32x32"},
    {"filename":"icon_128x128.png","idiom":"mac","scale":"1x","size":"128x128"},
    {"filename":"icon_128x128@2x.png","idiom":"mac","scale":"2x","size":"128x128"},
    {"filename":"icon_256x256.png","idiom":"mac","scale":"1x","size":"256x256"},
    {"filename":"icon_256x256@2x.png","idiom":"mac","scale":"2x","size":"256x256"},
    {"filename":"icon_512x512.png","idiom":"mac","scale":"1x","size":"512x512"},
    {"filename":"icon_512x512@2x.png","idiom":"mac","scale":"2x","size":"512x512"}
  ],
  "info": {"author":"xcode","version":1}
}
ICONJSON
        # Compile Asset Catalog — produces Assets.car which modern macOS needs
        xcrun actool "$XCASSETS_DIR" \
            --compile "${APP_DIR}/Contents/Resources" \
            --platform macosx \
            --minimum-deployment-target 13.0 \
            --app-icon AppIcon \
            --output-partial-info-plist /tmp/vocamac-icon-partial.plist 2>/dev/null && \
            echo "📎 App icon compiled (Assets.car)" || \
            echo "📎 App icon copied (.icns only — actool unavailable)"

        rm -rf "$ICONSET_DIR" "$XCASSETS_DIR" /tmp/vocamac-icon-partial.plist 2>/dev/null
    else
        echo "📎 App icon copied (.icns only)"
    fi
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
    <string>0.3.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
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
    codesign --force --sign "$CODE_SIGN_IDENTITY" {} \; 2>/dev/null || true

# Sign the main app
codesign --force --sign "$CODE_SIGN_IDENTITY" \
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
    if [ "$CODE_SIGN_IDENTITY" = "-" ]; then
        echo ""
        echo "   ⚠️  Permissions reset on every rebuild (ad-hoc signing limitation)."
        echo "   💡 TIP: To avoid this, add your Terminal app to Accessibility & Input Monitoring"
        echo "      and run VocaMac directly: .build/arm64-apple-macosx/release/VocaMac"
    fi
fi
