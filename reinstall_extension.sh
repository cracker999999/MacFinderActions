#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID="com.leen.FinderActions.FinderSyncExt"
LOCAL_DERIVED="$ROOT/.DerivedData"
export LOCAL_DERIVED

APP=$(python3 - <<'PY'
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

if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "No signed FinderActions.app found in ~/Library/Developer/Xcode/DerivedData." >&2
  echo "Please run FinderActions once in Xcode with valid signing, then rerun." >&2
  exit 1
fi

APPEX="$APP/Contents/PlugIns/FinderActionsFinderSyncExt.appex"

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/FinderActions.app"
cp -R "$APP" "$HOME/Applications/FinderActions.app"
xattr -dr com.apple.quarantine "$HOME/Applications/FinderActions.app" 2>/dev/null || true
xattr -dr com.apple.provenance "$HOME/Applications/FinderActions.app" 2>/dev/null || true

# Register app and extension explicitly
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$LSREGISTER" -f "$HOME/Applications/FinderActions.app" >/dev/null 2>&1 || true
pluginkit -a "$HOME/Applications/FinderActions.app/Contents/PlugIns/FinderActionsFinderSyncExt.appex" || true
pluginkit -e use -i "$BUNDLE_ID" || true

# Restart extension host and Finder
killall FinderActionsFinderSyncExt 2>/dev/null || true
killall Finder 2>/dev/null || true
open -n -a "$HOME/Applications/FinderActions.app" >/dev/null 2>&1 || true

echo "Reinstalled to: $HOME/Applications/FinderActions.app"
echo "Now enable extension in System Settings -> Privacy & Security -> Extensions -> Finder Extensions."
echo "Then test blank area right-click in a folder under your home directory."
