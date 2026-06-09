#!/bin/bash
set -euo pipefail

# TSX Deck build script
# Produces universal binary + properly signed .app with hardened runtime.
# Only ships the EXAMPLE config (real creds must live in App Support).

APP_NAME="TSX Deck"
EXECUTABLE_NAME="TopstepXFloatPanel"
BUNDLE_ID="local.topstepx.TopstepXFloatPanel"   # Change to your real reverse-DNS ID if you have a Developer cert
MIN_OS="14.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/topstepx_float_panel.swift"
RES_DIR="$SCRIPT_DIR/Resources"
OUT_APP="$SCRIPT_DIR/$APP_NAME.app"
BARE_OUT="$SCRIPT_DIR/$EXECUTABLE_NAME"

echo "=== Building $APP_NAME (universal + hardened) ==="
echo "Source: $SRC"
echo "Resources: $RES_DIR"

# Clean previous app bundle (but keep other artifacts)
rm -rf "$OUT_APP"
mkdir -p "$OUT_APP/Contents/"{MacOS,Resources}

# 1. Build two thin binaries
ARM64_BIN="/tmp/${EXECUTABLE_NAME}-arm64-$$"
X86_BIN="/tmp/${EXECUTABLE_NAME}-x86_64-$$"

echo "→ Building arm64..."
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macos${MIN_OS} \
  -framework AppKit -framework Foundation \
  -file-prefix-map "$SCRIPT_DIR=." \
  "$SRC" -o "$ARM64_BIN"

echo "→ Building x86_64..."
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" \
  -target x86_64-apple-macos${MIN_OS} \
  -framework AppKit -framework Foundation \
  -file-prefix-map "$SCRIPT_DIR=." \
  "$SRC" -o "$X86_BIN"

echo "→ Creating universal binary..."
lipo -create "$ARM64_BIN" "$X86_BIN" -output "$OUT_APP/Contents/MacOS/$EXECUTABLE_NAME"
rm -f "$ARM64_BIN" "$X86_BIN"

chmod +x "$OUT_APP/Contents/MacOS/$EXECUTABLE_NAME"

# Also produce bare standalone for quick testing
cp "$OUT_APP/Contents/MacOS/$EXECUTABLE_NAME" "$BARE_OUT"
chmod +x "$BARE_OUT"
echo "→ Bare binary: $BARE_OUT"

# 2. Copy safe resources only (example config, never real creds)
echo "→ Copying resources (example config only)..."
cp "$RES_DIR/topstepx_icon.icns" "$OUT_APP/Contents/Resources/"
cp "$RES_DIR/topstepx_icon.png" "$OUT_APP/Contents/Resources/" 2>/dev/null || true

# Always ship the EXAMPLE as the bundled config
cp "$RES_DIR/topstepx_config.example.json" "$OUT_APP/Contents/Resources/topstepx_config.json"

# Optional: copy sounds if present (for bundled sound support)
for caf in "$SCRIPT_DIR"/*.caf "$RES_DIR"/*.caf; do
  if [ -f "$caf" ]; then
    cp "$caf" "$OUT_APP/Contents/Resources/" || true
    echo "   + sound: $(basename "$caf")"
  fi
done

# 3. Install Info.plist (the improved one)
cp "$RES_DIR/Info.plist" "$OUT_APP/Contents/Info.plist"

# 4. Entitlements + hardened sign (adhoc with runtime for now)
cat > /tmp/entitlements.$$.plist << 'EOP'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOP

echo "→ Signing with hardened runtime..."
codesign --force --options runtime --timestamp --deep \
  --entitlements /tmp/entitlements.$$.plist \
  -s - \
  "$OUT_APP"

rm -f /tmp/entitlements.$$.plist

echo "✅ Done: $OUT_APP"
echo "   (universal, hardened, example config only, LSUIElement-enabled float panel behavior)"
echo ""
echo "To test: open $OUT_APP"
echo "Real config should now live at: ~/Library/Application Support/TopstepXFloatPanel/topstepx_config.json"
