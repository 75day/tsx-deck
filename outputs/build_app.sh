#!/bin/bash
set -euo pipefail

# TSX Deck build script
# Produces universal binary + properly signed .app with hardened runtime.
#
# For easy transfer between your own Macs:
# - You can place a real topstepx_config.json in this outputs/ folder.
# - The build will bundle it into the .app so the whole folder becomes
#   self-contained for direct copy & use on another of your computers.
# - If no real config is present here, only the safe example is bundled.

APP_NAME="TSX Deck"
EXECUTABLE_NAME="TopstepXFloatPanel"
BUNDLE_ID="local.topstepx.TopstepXFloatPanel"   # Change to your real reverse-DNS ID if you have a Developer cert
MIN_OS="14.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/topstepx_float_panel.swift"
CORE_SRC="$SCRIPT_DIR/TSXDeckCore.swift"
CONTROLS_SRC="$SCRIPT_DIR/TSXDeckControls.swift"
VIEWS_SRC="$SCRIPT_DIR/TSXDeckSectionViews.swift"
LAYOUT_SRC="$SCRIPT_DIR/PanelController+Layout.swift"
TEXT_SRC="$SCRIPT_DIR/PanelController+Text.swift"
TICKET_UI_SRC="$SCRIPT_DIR/PanelController+TicketUI.swift"
TICKET_STATE_SRC="$SCRIPT_DIR/PanelController+TicketState.swift"
WORKING_ORDERS_SRC="$SCRIPT_DIR/PanelController+WorkingOrders.swift"
MAIN_SRC="$SCRIPT_DIR/main.swift"
RES_DIR="$SCRIPT_DIR/Resources"
OUT_APP="$SCRIPT_DIR/$APP_NAME.app"
BARE_OUT="$SCRIPT_DIR/$EXECUTABLE_NAME"

echo "=== Building $APP_NAME (universal + hardened) ==="
echo "Source: $SRC"
echo "Core: $CORE_SRC"
echo "Controls: $CONTROLS_SRC"
echo "Views: $VIEWS_SRC"
echo "Layout: $LAYOUT_SRC"
echo "Text: $TEXT_SRC"
echo "Ticket UI: $TICKET_UI_SRC"
echo "Ticket State: $TICKET_STATE_SRC"
echo "Working Orders: $WORKING_ORDERS_SRC"
echo "Main: $MAIN_SRC"
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
  "$CORE_SRC" "$CONTROLS_SRC" "$VIEWS_SRC" "$SRC" "$LAYOUT_SRC" "$TEXT_SRC" "$TICKET_UI_SRC" "$TICKET_STATE_SRC" "$WORKING_ORDERS_SRC" "$MAIN_SRC" -o "$ARM64_BIN"

echo "→ Building x86_64..."
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" \
  -target x86_64-apple-macos${MIN_OS} \
  -framework AppKit -framework Foundation \
  -file-prefix-map "$SCRIPT_DIR=." \
  "$CORE_SRC" "$CONTROLS_SRC" "$VIEWS_SRC" "$SRC" "$LAYOUT_SRC" "$TEXT_SRC" "$TICKET_UI_SRC" "$TICKET_STATE_SRC" "$WORKING_ORDERS_SRC" "$MAIN_SRC" -o "$X86_BIN"

echo "→ Creating universal binary..."
lipo -create "$ARM64_BIN" "$X86_BIN" -output "$OUT_APP/Contents/MacOS/$EXECUTABLE_NAME"
rm -f "$ARM64_BIN" "$X86_BIN"

chmod +x "$OUT_APP/Contents/MacOS/$EXECUTABLE_NAME"

# Also produce bare standalone for quick testing
cp "$OUT_APP/Contents/MacOS/$EXECUTABLE_NAME" "$BARE_OUT"
chmod +x "$BARE_OUT"
echo "→ Bare binary: $BARE_OUT"

# 2. Copy resources
echo "→ Copying resources..."
cp "$RES_DIR/topstepx_icon.icns" "$OUT_APP/Contents/Resources/"
cp "$RES_DIR/topstepx_icon.png" "$OUT_APP/Contents/Resources/" 2>/dev/null || true

# Config handling for easy transfer between your own Macs:
# Place your real topstepx_config.json directly in this outputs/ folder (next to build_app.sh).
# If present, it will be bundled into the .app so you can copy the whole folder
# and run the app directly on another of your Macs with minimal hassle.
# If no real config is here, the safe example is used instead.
if [ -f "$SCRIPT_DIR/topstepx_config.json" ]; then
    echo "   Using real topstepx_config.json from this folder (bundled for direct use on other Macs)"
    cp "$SCRIPT_DIR/topstepx_config.json" "$OUT_APP/Contents/Resources/topstepx_config.json"
else
    echo "   No real topstepx_config.json found here. Bundling the example only."
    cp "$RES_DIR/topstepx_config.example.json" "$OUT_APP/Contents/Resources/topstepx_config.json"
fi

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

# Touch the app bundle to help macOS notice changes (reduces icon cache problems)
touch "$OUT_APP"

echo "✅ Done: $OUT_APP"
echo "   (universal, hardened runtime, LSUIElement-enabled float panel)"
echo ""
echo "To test: open $OUT_APP"
echo ""
echo "Transfer note:"
echo "  - If you put your real topstepx_config.json in this outputs/ folder before building,"
echo "    it is now bundled inside the .app."
echo "  - You can copy the entire outputs/ folder to another of your Macs and run the .app directly"
echo "    (or re-run ./build_app.sh there for a fresh ad-hoc signature)."
echo "  - See PORTABLE_README.txt in this folder for full instructions."
echo ""
echo "If the app icon appears white in Finder after build/copy:"
echo "  touch \"$OUT_APP\""
echo "  killall Dock"
echo "Then reopen the folder in Finder (or log out and back in if needed)."
