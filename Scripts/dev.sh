#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/Scripts/package_app.sh" debug

if pgrep -x Chum > /dev/null 2>&1; then
    pkill -x Chum || true
    sleep 0.3
fi

# Launch the executable directly instead of `open`: `open` registers the repo
# bundle in LaunchServices, and a second com.chum.app registration (dev copy
# + /Applications) makes Spotlight hide the app from search results.
nohup "$ROOT/Chum.app/Contents/MacOS/Chum" >/dev/null 2>&1 &
disown
echo "Chum launched"
