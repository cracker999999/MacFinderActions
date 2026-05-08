#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.leen.FinderActions.FinderSyncExt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$HOME/Library/Developer/Xcode/DerivedData"
LOCAL_DERIVED="$SCRIPT_DIR/.DerivedData"
APP_DST="$HOME/Applications/FinderActions.app"
APPEX_DST="$APP_DST/Contents/PlugIns/FinderActionsFinderSyncExt.appex"
export LOCAL_DERIVED

# Always refresh from latest SIGNED Xcode Debug build (never from local unsigned CLI build).
latest_app=$(python3 - <<'PY'
import os
from pathlib import Path
import subprocess

roots = [
    Path(os.path.expanduser("~/Library/Developer/Xcode/DerivedData")),
    Path(os.environ.get("LOCAL_DERIVED", ""))
]
candidates = []
for root in roots:
    if root and root.exists():
        candidates.extend(root.glob("*/Build/Products/Debug/FinderActions.app"))
        candidates.extend(root.glob("Build/Products/Debug/FinderActions.app"))
candidates = list(dict.fromkeys(candidates))
signed = []
for p in candidates:
    r = subprocess.run(["codesign", "-dv", str(p)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode == 0:
        signed.append(p)

if signed:
    newest = max(signed, key=lambda p: p.stat().st_mtime)
    print(str(newest))
else:
    print("")
PY
)

if [[ -n "$latest_app" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$APP_DST"
  cp -R "$latest_app" "$APP_DST"
  xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
  xattr -dr com.apple.provenance "$APP_DST" 2>/dev/null || true
else
  echo "No signed FinderActions.app found in ~/Library/Developer/Xcode/DerivedData." >&2
  echo "Please run FinderActions once from Xcode (with valid Signing Team), then rerun this script." >&2
  exit 1
fi

if [[ ! -d "$APPEX_DST" ]]; then
  echo "Missing extension at: $APPEX_DST" >&2
  echo "Please build and run FinderActions target once in Xcode first." >&2
  exit 1
fi

echo "== Remove old registrations =="
pluginkit -m -A -D -v -i "$BUNDLE_ID" 2>/dev/null \
  | awk '{print $NF}' \
  | grep -E '\.appex$' \
  | while read -r p; do
      if [[ "$p" != "$APPEX_DST" ]]; then
        echo "remove: $p"
        pluginkit -r "$p" || true
      fi
    done

echo "== Register desired extension =="
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$LSREGISTER" -f "$APP_DST" >/dev/null 2>&1 || true
pluginkit -a "$APPEX_DST" || true
pluginkit -e ignore -i "$BUNDLE_ID" || true
pluginkit -e use -i "$BUNDLE_ID" || true

echo "== Restart Finder and app =="
killall FinderActionsFinderSyncExt 2>/dev/null || true
killall Finder 2>/dev/null || true
open -n -a "$APP_DST" >/dev/null 2>&1 || true

sleep 1

echo
echo "== Current status =="
pluginkit -m -A -D -v -i "$BUNDLE_ID" || true

echo
echo "Now in System Settings -> Privacy & Security -> Extensions -> Finder Extensions"
echo "toggle OFF then ON for 'Finder Actions Extension', then run: killall Finder"
