#!/bin/bash
# Builds the app, copies it to /Applications and launches it.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh

DEST="/Applications/Pomodoraaa.app"
if pgrep -x Pomodoraaa >/dev/null; then
  echo "→ Quitting the running copy…"
  pkill -x Pomodoraaa || true
  sleep 1
fi

echo "→ Installing to $DEST"
rm -rf "$DEST"
cp -R build/Pomodoraaa.app "$DEST"

open "$DEST"
echo "✓ Pomodoraaa is running — look for the timer icon in your menu bar."
