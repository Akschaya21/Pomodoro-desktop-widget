#!/bin/bash
# Builds build/Pomodoraaa.app from the Swift package.
# Needs only the Xcode Command Line Tools:  xcode-select --install
set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Pomodoraaa"

APP="build/Pomodoraaa.app"
echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pomodoraaa"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# Ad-hoc signature so macOS lets it run locally and remembers its permissions.
codesign --force --deep --sign - "$APP" >/dev/null

echo "✓ Built $APP"
