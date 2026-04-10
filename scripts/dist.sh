#!/bin/bash
# dist.sh — Build VocaMac and package as a signed, notarized DMG
# Usage: ./scripts/dist.sh [--skip-notarize] [--skip-sign]
#
# This script:
# 1. Builds VocaMac.app via build.sh (Developer ID signed if available)
# 2. Creates a beautiful DMG with:
#    - Branded background image with install instructions
#    - App icon on the left, Applications symlink on the right
#    - Properly sized and positioned Finder window
#    - README.txt with permission setup instructions
# 3. Signs the DMG with Developer ID
# 4. Notarizes with Apple and staples the ticket
#
# Environment variables:
#   CODE_SIGN_IDENTITY   — Passed through to build.sh
#   NOTARIZE_PROFILE     — Keychain profile name for notarytool (default: AC_PASSWORD)
#
# Flags:
#   --skip-notarize      — Build and sign but skip notarization (for local testing)
#   --skip-sign          — Skip signing entirely (ad-hoc only, Gatekeeper will block)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Parse flags
SKIP_NOTARIZE=false
SKIP_SIGN=false
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --skip-sign)     SKIP_SIGN=true; SKIP_NOTARIZE=true ;;
    esac
done

# Get version from build.sh's Info.plist template
VERSION=$(grep -A1 'CFBundleShortVersionString' scripts/build.sh | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/' | head -1)
ARCH=$(uname -m)
APP_NAME="VocaMac"
DMG_NAME="${APP_NAME}-${VERSION}-${ARCH}.dmg"
DIST_DIR="dist"
STAGING_DIR="${DIST_DIR}/.staging"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-AC_PASSWORD}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VocaMac ${VERSION} — Distribution Build"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Build ────────────────────────────────────────────────────────────
echo "▶ Step 1/5: Building VocaMac..."
"$SCRIPT_DIR/build.sh" release

if [ ! -d "VocaMac.app" ]; then
    echo "❌ VocaMac.app not found. Build failed."
    exit 1
fi

# Grab the actual signing identity from Keychain (same logic as build.sh)
SIGNING_IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
echo "   Signed with: ${SIGNING_IDENTITY:-ad-hoc}"
echo ""

# ── Step 2: Stage DMG contents ───────────────────────────────────────────────
echo "▶ Step 2/5: Staging DMG contents..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$DIST_DIR"

# Copy app
cp -R VocaMac.app "$STAGING_DIR/"

# Applications symlink
ln -sf /Applications "$STAGING_DIR/Applications"

# Copy branded background (hidden folder — standard DMG convention)
mkdir -p "$STAGING_DIR/.background"
if [ -f "Sources/VocaMac/Resources/dmg-background.png" ]; then
    cp "Sources/VocaMac/Resources/dmg-background.png"    "$STAGING_DIR/.background/background.png"
fi
if [ -f "Sources/VocaMac/Resources/dmg-background@2x.png" ]; then
    cp "Sources/VocaMac/Resources/dmg-background@2x.png" "$STAGING_DIR/.background/background@2x.png"
fi

# No README.txt — instructions are on the background image and website
echo "   Staging complete."
echo ""

# ── Step 3: Create DMG ───────────────────────────────────────────────────────
echo "▶ Step 3/5: Creating DMG..."

# Create a writable DMG first so we can set Finder view options
TEMP_DMG="${DIST_DIR}/.tmp-rw.dmg"
hdiutil create -volname "VocaMac" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDRW \
    -size 500m \
    "$TEMP_DMG" > /dev/null

# Mount it
MOUNT_POINT=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen \
    | grep -E '\s/Volumes/' | sed 's|.*\(/Volumes/[^\t]*\)|\1|' | tail -1 | xargs)

if [ -z "$MOUNT_POINT" ]; then
    echo "❌ Failed to mount DMG."
    exit 1
fi

echo "   Mounted at: $MOUNT_POINT"

# Set Finder window layout via AppleScript
# We run this in a loop because Finder can be slow to register the volume,
# and we need the .DS_Store to be written before we detach.
echo "   Configuring Finder layout..."

# Ensure any previous VocaMac volumes are ejected first
for vol in /Volumes/VocaMac*; do
    [ -d "$vol" ] && [ "$vol" != "$MOUNT_POINT" ] && hdiutil detach "$vol" 2>/dev/null || true
done

# Give Finder time to discover the volume
sleep 2

osascript << 'APPLESCRIPT'
tell application "Finder"
    tell disk "VocaMac"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 60, 860, 580}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set background picture of viewOptions to file ".background:background.png"
        set position of item "VocaMac.app" of container window to {170, 250}
        set position of item "Applications" of container window to {490, 250}
        close
        open
        delay 1
        -- Force a second pass to ensure settings stick
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 60, 860, 580}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set background picture of viewOptions to file ".background:background.png"
        set position of item "VocaMac.app" of container window to {170, 250}
        set position of item "Applications" of container window to {490, 250}
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

# Ensure .DS_Store is flushed to disk
sync
sleep 1

# Verify .DS_Store was written
if [ -f "$MOUNT_POINT/.DS_Store" ]; then
    echo "   Finder layout applied (.DS_Store written)"
else
    echo "   ⚠️  .DS_Store not found — Finder layout may not persist"
fi

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet || hdiutil detach "$MOUNT_POINT" -force

# Convert to compressed final DMG
FINAL_DMG="${DIST_DIR}/${DMG_NAME}"
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL_DMG" > /dev/null
rm -f "$TEMP_DMG"

echo "   DMG created: ${FINAL_DMG}"
echo ""

# ── Step 4: Sign DMG ─────────────────────────────────────────────────────────
echo "▶ Step 4/5: Signing DMG..."

if [ "$SKIP_SIGN" = true ]; then
    echo "   ⚠️  Skipped (--skip-sign)"
elif [ -z "$SIGNING_IDENTITY" ]; then
    echo "   ⚠️  No Developer ID found — DMG not signed (Gatekeeper will block)"
else
    codesign --sign "$SIGNING_IDENTITY" "$FINAL_DMG"
    echo "   Signed with: $SIGNING_IDENTITY"
fi
echo ""

# ── Step 5: Notarize ─────────────────────────────────────────────────────────
echo "▶ Step 5/5: Notarizing..."

if [ "$SKIP_NOTARIZE" = true ]; then
    echo "   ⚠️  Skipped (--skip-notarize)"
elif [ -z "$SIGNING_IDENTITY" ]; then
    echo "   ⚠️  Skipped — no Developer ID certificate"
else
    # Check that the notarization keychain profile exists
    if ! xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" > /dev/null 2>&1; then
        echo "   ❌ Notarization keychain profile '$NOTARIZE_PROFILE' not found."
        echo "      Run: xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" \\"
        echo "               --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID"
        echo "      Then re-run: ./scripts/dist.sh"
        exit 1
    fi

    echo "   Submitting to Apple Notary Service (this takes 1–5 minutes)..."
    xcrun notarytool submit "$FINAL_DMG" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait

    echo "   Stapling notarization ticket..."
    xcrun stapler staple "$FINAL_DMG"
    echo "   Notarization complete."
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Distribution build complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  File:    ${FINAL_DMG}"
echo "  Size:    $(du -h "${FINAL_DMG}" | cut -f1)"
echo ""
echo "  SHA-256: $(shasum -a 256 "${FINAL_DMG}" | awk '{print $1}')"
echo ""
echo "  Path:    $(cd "$(dirname "$FINAL_DMG")" && pwd)/$(basename "$FINAL_DMG")"

# Clean up staging
rm -rf "$STAGING_DIR"
