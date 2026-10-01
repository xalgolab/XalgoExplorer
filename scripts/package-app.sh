#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/xAlgo Explorer.app"
EXECUTABLE="$ROOT_DIR/.build/release/xAlgoExplorer"
APP_ICON="$ROOT_DIR/Sources/xAlgoExplorer/Resources/AppIcon.icns"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing release executable. Run: swift build -c release" >&2
  exit 1
fi

if [[ ! -f "$APP_ICON" ]]; then
  echo "Missing app icon: $APP_ICON" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/xAlgoExplorer"
cp "$APP_ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>xAlgoExplorer</string>
  <key>CFBundleIdentifier</key>
  <string>com.xalgo.explorer</string>
  <key>CFBundleName</key>
  <string>xAlgo Explorer</string>
  <key>CFBundleDisplayName</key>
  <string>xAlgo Explorer</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>v0.2.0-candidate</string>
  <key>CFBundleVersion</key>
  <string>3</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
