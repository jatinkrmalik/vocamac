#!/bin/bash
# install.sh — Install VocaMac for easy daily use
#
# Creates a 'vocamac' command in ~/.local/bin (no sudo required).
# Run this script once after cloning. Rebuild anytime with: vocamac-build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

LOCAL_BIN="$HOME/.local/bin"
BINARY="$(pwd)/.build/arm64-apple-macosx/release/VocaMac"

echo "🔨 Building VocaMac (release)..."
swift build -c release 2>&1 | tail -3

if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed"
    exit 1
fi

# Create ~/.local/bin if it doesn't exist
mkdir -p "$LOCAL_BIN"

# Create launcher script
cat > "$LOCAL_BIN/vocamac" << EOF
#!/bin/bash
# VocaMac launcher — local voice-to-text for macOS
# Kill any existing instance and launch fresh
pkill -f "VocaMac" 2>/dev/null
sleep 0.5
exec "$BINARY" "\$@"
EOF
chmod +x "$LOCAL_BIN/vocamac"

# Create a rebuild shortcut
cat > "$LOCAL_BIN/vocamac-build" << EOF
#!/bin/bash
# Rebuild VocaMac from source
cd "$PROJECT_DIR"
pkill -f "VocaMac" 2>/dev/null
swift build -c release 2>&1 | tail -3
echo "✅ VocaMac rebuilt. Run 'vocamac &' to launch."
EOF
chmod +x "$LOCAL_BIN/vocamac-build"

echo ""
echo "✅ VocaMac installed!"
echo ""

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    echo "⚠️  Add ~/.local/bin to your PATH. Add this to your ~/.zshrc:"
    echo ""
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "   Then run: source ~/.zshrc"
    echo ""
fi

echo "📋 Commands:"
echo "   vocamac &         — Launch VocaMac in background"
echo "   vocamac-build     — Rebuild from source"
echo "   killall VocaMac   — Stop VocaMac"
echo ""
echo "⚠️  First time? Grant these permissions to Terminal.app:"
echo "   System Settings → Privacy & Security → Accessibility → Terminal → ON"
echo "   System Settings → Privacy & Security → Input Monitoring → Terminal → ON"
echo "   System Settings → Privacy & Security → Microphone → Terminal → ON"
echo ""
echo "🎤 Usage:"
echo "   1. Run: vocamac &"
echo "   2. Click into any text field"
echo "   3. Hold Right Option → speak → release"
echo "   4. Text appears at your cursor!"
