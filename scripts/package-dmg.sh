#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/xAlgo Explorer.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
STAGE_DIR="$ROOT_DIR/dist/dmg-root"
VERSION="v0.2.0-candidate"
ARCH_NAME="aarch64"
VOL_NAME="xAlgo Explorer"
DMG_PATH="$ROOT_DIR/dist/xAlgo_Explorer_${VERSION}_${ARCH_NAME}.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle: $APP_DIR" >&2
  echo "Run: make app" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist: $INFO_PLIST" >&2
  exit 1
fi

if command -v plutil >/dev/null 2>&1; then
  VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
fi

case "$(uname -m)" in
  arm64) ARCH_NAME="aarch64" ;;
  x86_64) ARCH_NAME="x86_64" ;;
esac

DMG_PATH="$ROOT_DIR/dist/xAlgo_Explorer_${VERSION}_${ARCH_NAME}.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

rm -rf "$STAGE_DIR" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -fs HFS+ \
  -ov \
  "$DMG_PATH"

(cd "$ROOT_DIR/dist" && shasum -a 256 "$(basename "$DMG_PATH")") > "$CHECKSUM_PATH"
rm -rf "$STAGE_DIR"

echo "$DMG_PATH"
