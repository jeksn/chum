#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Chum"
BUNDLE_ID="com.chum.app"
VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")"

cd "$ROOT"
swift build -c "$CONFIG"

BIN_PATH="$(swift build --show-bin-path -c "$CONFIG")"
APP_BUNDLE="$ROOT/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

for bundle in "$BIN_PATH"/*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
done

python3 - "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$BIN_PATH" <<'PY'
import re, sys
bin_path, bin_dir = sys.argv[1], sys.argv[2].rstrip('/')
resources = "/Applications/Chum.app/Contents/Resources"
data = bytearray(open(bin_path, 'rb').read())
patched = 0
for m in re.finditer(re.escape(bin_dir.encode()) + rb'/[A-Za-z0-9_]+_[A-Za-z0-9_]+\.bundle', data):
    old = m.group(0)
    name = old.rsplit(b'/', 1)[-1]
    new = resources.encode() + b'/' + name
    new += b'/' * (len(old) - len(new))
    data[m.start():m.end()] = new
    patched += 1
open(bin_path, 'wb').write(data)
print(f'patched {patched} resource bundle path(s)')
PY

ICON_KEY=""
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
  ICON_KEY="  <key>CFBundleIconFile</key><string>AppIcon</string>"
fi

if [[ -f "$ROOT/Resources/MenuBarIcon.png" ]]; then
  cp "$ROOT/Resources/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key>
      <array><string>chum</string></array>
    </dict>
  </array>
  $ICON_KEY
</dict>
</plist>
PLIST

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" && -f "$ROOT/Scripts/codesign-identity" ]]; then
  SIGN_IDENTITY="$(head -n 1 "$ROOT/Scripts/codesign-identity" | xargs)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi
# A named identity that isn't in the keychain (e.g. after a rename, before the
# new cert exists) falls back to ad-hoc instead of failing the build.
if [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
  echo "warning: signing identity \"$SIGN_IDENTITY\" not found in the keychain — signing ad-hoc"
  SIGN_IDENTITY="-"
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Built $APP_BUNDLE (ad-hoc signed)"
  echo "Note: ad-hoc signatures change on every rebuild, which invalidates the macOS"
  echo "Accessibility grant. For stable permissions, create a self-signed Code Signing"
  echo "certificate and put its name in Scripts/codesign-identity (or export CODESIGN_IDENTITY)."
else
  echo "Built $APP_BUNDLE (signed with \"$SIGN_IDENTITY\")"
fi
