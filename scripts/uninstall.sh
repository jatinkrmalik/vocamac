#!/bin/bash
# uninstall.sh — Completely remove VocaMac and all its data
#
# This gives you a clean slate:
#   - Kills any running VocaMac process
#   - Removes downloaded models (~/.../Application Support/VocaMac/)
#   - Removes launcher scripts (~/.local/bin/vocamac*)
#   - Removes CoreML compilation cache
#   - Removes the .app bundle if it exists
#   - Optionally cleans build artifacts
#
# Usage: ./scripts/uninstall.sh [--keep-build]
#   --keep-build    Skip cleaning .build/ directory (useful if you're just resetting app data)

set -euo pipefail

KEEP_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --keep-build) KEEP_BUILD=true ;;
        -h|--help)
            echo "Usage: ./scripts/uninstall.sh [--keep-build]"
            echo "  --keep-build    Skip cleaning .build/ directory"
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🗑️  VocaMac Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Kill running process
echo "→ Stopping VocaMac..."
pkill -f "VocaMac" 2>/dev/null && echo "  ✓ Process killed" || echo "  · Not running"
sleep 0.5

# 2. Remove Application Support data (models, caches)
APP_SUPPORT="$HOME/Library/Application Support/VocaMac"
if [ -d "$APP_SUPPORT" ]; then
    # Show what we're deleting
    MODEL_SIZE=$(du -sh "$APP_SUPPORT" 2>/dev/null | cut -f1)
    echo "→ Removing app data ($MODEL_SIZE)..."
    echo "  $APP_SUPPORT"
    rm -rf "$APP_SUPPORT"
    echo "  ✓ App data removed"
else
    echo "→ No app data found"
fi

# 3. Remove CoreML compilation cache (compiled model artifacts)
COREML_CACHE="$HOME/Library/Caches/com.apple.CoreML"
if [ -d "$COREML_CACHE" ]; then
    echo "→ Clearing CoreML cache..."
    rm -rf "$COREML_CACHE"
    echo "  ✓ CoreML cache cleared"
fi

# 4. Remove launcher scripts
echo "→ Removing launcher scripts..."
REMOVED_SCRIPTS=0
for script in "$HOME/.local/bin/vocamac" "$HOME/.local/bin/vocamac-build"; do
    if [ -f "$script" ]; then
        rm -f "$script"
        echo "  ✓ Removed $script"
        REMOVED_SCRIPTS=$((REMOVED_SCRIPTS + 1))
    fi
done
if [ "$REMOVED_SCRIPTS" -eq 0 ]; then
    echo "  · No launcher scripts found"
fi

# 5. Remove .app bundle
APP_BUNDLE="$PROJECT_DIR/VocaMac.app"
if [ -d "$APP_BUNDLE" ]; then
    echo "→ Removing app bundle..."
    rm -rf "$APP_BUNDLE"
    echo "  ✓ Removed $APP_BUNDLE"
else
    echo "→ No app bundle found"
fi

# Also check /Applications
for app_dir in "/Applications/VocaMac.app" "$HOME/Applications/VocaMac.app"; do
    if [ -d "$app_dir" ]; then
        echo "→ Removing $app_dir..."
        rm -rf "$app_dir" 2>/dev/null && echo "  ✓ Removed" || echo "  ⚠️  Could not remove (try: sudo rm -rf \"$app_dir\")"
    fi
done

# 6. Remove UserDefaults/preferences
echo "→ Removing preferences..."
defaults delete com.vocamac.VocaMac 2>/dev/null && echo "  ✓ Preferences cleared" || echo "  · No preferences found"
defaults delete com.vocamac.app 2>/dev/null && echo "  ✓ App preferences cleared" || true

# 7. Clean build artifacts
if [ "$KEEP_BUILD" = false ]; then
    echo "→ Cleaning build artifacts..."
    if [ -d "$PROJECT_DIR/.build" ]; then
        rm -rf "$PROJECT_DIR/.build"
        echo "  ✓ .build/ removed"
    else
        echo "  · No build artifacts found"
    fi
else
    echo "→ Skipping build artifacts (--keep-build)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━"
echo "✅ VocaMac fully uninstalled!"
echo ""
echo "To reinstall:"
echo "  ./scripts/build.sh && ./scripts/install.sh"
echo ""
echo "⚠️  Note: Accessibility and Input Monitoring permissions in"
echo "   System Settings → Privacy & Security must be removed manually."
