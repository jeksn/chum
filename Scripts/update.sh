#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications/Chum.app"

"$ROOT/Scripts/package_app.sh"

if pgrep -x Chum > /dev/null 2>&1; then
    pkill -x Chum || true
    sleep 0.3
fi

rm -rf "$DEST"
cp -R "$ROOT/Chum.app" "$DEST"
open "$DEST"
echo "Installed and launched $DEST"
