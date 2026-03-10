#!/bin/bash
# dist.sh — Build VocaMac and package as a DMG
# Usage: ./scripts/dist.sh
#
# This script:
# 1. Builds VocaMac.app via build.sh
# 2. Creates a DMG with the app and an Applications symlink
# 3. Outputs the DMG to dist/
#
# All artifacts are placed in dist/ — a single, clean output directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Get version from build.sh's Info.plist template
VERSION=$(grep -A1 'CFBundleShortVersionString' scripts/build.sh | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>/\1/' | head -1)
ARCH=$(uname -m)
DMG_NAME="VocaMac-${VERSION}-${ARCH}.dmg"
DIST_DIR="dist"
STAGING_DIR="${DIST_DIR}/.staging"

# Build the app first
echo "🔨 Building VocaMac..."
"$SCRIPT_DIR/build.sh" release

if [ ! -d "VocaMac.app" ]; then
    echo "❌ VocaMac.app not found. Build failed."
    exit 1
fi

# Clean and prepare dist directory
echo "📦 Preparing distribution..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$DIST_DIR"

# Stage the app and Applications symlink
cp -R VocaMac.app "$STAGING_DIR/"
ln -sf /Applications "$STAGING_DIR/Applications"

# Create the DMG
echo "💿 Creating DMG..."
hdiutil create -volname "VocaMac" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "${DIST_DIR}/${DMG_NAME}"

# Clean up staging
rm -rf "$STAGING_DIR"

echo ""
echo "✅ DMG created!"
echo ""
echo "   File: ${DIST_DIR}/${DMG_NAME}"
echo "   Size: $(du -h "${DIST_DIR}/${DMG_NAME}" | cut -f1)"
echo ""
echo "   SHA-256:"
echo "   $(shasum -a 256 "${DIST_DIR}/${DMG_NAME}")"
echo ""
echo "🚀 To test:  open ${DIST_DIR}/${DMG_NAME}"
