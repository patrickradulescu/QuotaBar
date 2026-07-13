#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/dist/QuotaBar.app"
DESTINATION="/Applications/QuotaBar.app"

"$ROOT/scripts/build-app.sh"
pkill -x QuotaBar >/dev/null 2>&1 || true
rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"
open "$DESTINATION"

echo "Installed $DESTINATION"
