#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")"
DMG="$ROOT/dist/Chum-$VERSION.dmg"

"$ROOT/Scripts/package_app.sh"

rm -rf "$ROOT/dist"
mkdir -p "$ROOT/dist/dmg"
cp -R "$ROOT/Chum.app" "$ROOT/dist/dmg/"
ln -s /Applications "$ROOT/dist/dmg/Applications"

hdiutil create -volname "Chum" -srcfolder "$ROOT/dist/dmg" \
  -ov -format UDZO "$DMG"
hdiutil verify "$DMG" > /dev/null
echo "Created $DMG"
