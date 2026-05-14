#!/bin/bash
# build-intel.sh
#
# EXPERIMENTAL: Cross-compile a VocaMac DMG for Intel (x86_64) Macs.
#
# VocaMac officially ships arm64-only because WhisperKit is built around
# the Apple Neural Engine. This script exists purely to produce a one-off
# experimental Intel build for community testing — there is no CI coverage,
# no stability guarantee, and transcription on Intel will be CPU-only and
# significantly slower than on Apple Silicon.
#
# Usage:
#   ./scripts/build-intel.sh              # build + sign + notarize x86_64 DMG
#   ./scripts/build-intel.sh --skip-notarize  # local-only test build
#
# Output:
#   dist/VocaMac-X.Y.Z-x86_64.dmg
#
# Requirements:
#   - Xcode with macOS SDK that supports x86_64 cross-compilation
#   - Developer ID Application certificate in Keychain (for signing)
#   - 'AC_PASSWORD' notarytool keychain profile (for notarization)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ⚠️  EXPERIMENTAL INTEL (x86_64) BUILD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  This build is unsupported. Transcription on Intel"
echo "  Macs will fall back to CPU and be noticeably slower"
echo "  than on Apple Silicon. Do not publish to the Releases"
echo "  page — share with testers only."
echo ""

export BUILD_ARCH=x86_64
exec "$SCRIPT_DIR/dist.sh" "$@"
