#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/dist/Mussol Feiner.app"
DESTINATION="/Applications/Mussol Feiner.app"

"$ROOT/scripts/build-app.sh" >/dev/null
if pgrep -x mussol-feiner >/dev/null 2>&1; then
  echo "Mussol Feiner is open. Quit it before installing a new build." >&2
  exit 1
fi

rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"
xattr -cr "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
open -n "$DESTINATION"
echo "$DESTINATION"
