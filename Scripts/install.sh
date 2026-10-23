#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications/Chum.app"

if [ ! -d "$ROOT/Chum.app" ]; then
    echo "Chum.app not found - run Scripts/package_app.sh first" >&2
    exit 1
fi

if [ -d "$DEST" ] && [ "${1:-}" != "--force" ]; then
    echo "$DEST already exists. Re-run with --force to overwrite." >&2
    exit 1
fi

rm -rf "$DEST"
cp -R "$ROOT/Chum.app" "$DEST"
echo "Installed $DEST"
echo "Note: launch-at-login works best from /Applications."
