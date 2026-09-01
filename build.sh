#!/bin/bash
# Builds Klipvault.app. No Xcode project, no package manager, no dependencies.
set -euo pipefail
cd "$(dirname "$0")"

APP="Klipvault.app"
BUILD="build"
BIN="$BUILD/Klipvault"

echo "→ compiling"
rm -rf "$BUILD" && mkdir -p "$BUILD"
swiftc -swift-version 5 -O \
  -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
  Sources/*.swift -o "$BIN"

echo "→ drawing icon"
ICONSET="$BUILD/Klipvault.iconset"
"$BIN" --makeicon "$ICONSET" >/dev/null 2>&1 || true
if [ -d "$ICONSET" ]; then iconutil -c icns "$ICONSET" -o "$BUILD/Klipvault.icns" || true; fi

echo "→ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Klipvault"
[ -f "$BUILD/Klipvault.icns" ] && cp "$BUILD/Klipvault.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Klipvault</string>
  <key>CFBundleDisplayName</key><string>Klipvault</string>
  <key>CFBundleIdentifier</key><string>app.klipvault</string>
  <key>CFBundleExecutable</key><string>Klipvault</string>
  <key>CFBundleIconFile</key><string>Klipvault</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key><string>Klipvault presses Command-V for you so a chosen item pastes into the app you were using.</string>
</dict>
</plist>
PLIST

echo "→ signing (ad-hoc)"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  (unsigned — fine for local use)"

echo "→ self-test"
"$APP/Contents/MacOS/Klipvault" --selftest

echo
echo "Built $APP"
echo "Install:  cp -R $APP /Applications/  &&  open /Applications/$APP"
