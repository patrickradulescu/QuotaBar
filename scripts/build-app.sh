#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/QuotaBar.app"
CONTENTS="$APP/Contents"

cd "$ROOT"
"$ROOT/scripts/verify-release-version.sh"

ARM_TRIPLE="arm64-apple-macosx13.0"
INTEL_TRIPLE="x86_64-apple-macosx13.0"

swift build -c release --triple "$ARM_TRIPLE" --product QuotaBar
swift build -c release --triple "$INTEL_TRIPLE" --product QuotaBar
swift build -c release --triple "$ARM_TRIPLE" --product QuotaBarAgyBridge
swift build -c release --triple "$INTEL_TRIPLE" --product QuotaBarAgyBridge

ARM_BIN_DIR="$(swift build -c release --triple "$ARM_TRIPLE" --show-bin-path)"
INTEL_BIN_DIR="$(swift build -c release --triple "$INTEL_TRIPLE" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"
xcrun lipo -create \
    "$ARM_BIN_DIR/QuotaBar" \
    "$INTEL_BIN_DIR/QuotaBar" \
    -output "$CONTENTS/MacOS/QuotaBar"
xcrun lipo -create \
    "$ARM_BIN_DIR/QuotaBarAgyBridge" \
    "$INTEL_BIN_DIR/QuotaBarAgyBridge" \
    -output "$CONTENTS/Helpers/QuotaBarAgyBridge"
cp "$ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
"$ROOT/scripts/make-icon.sh" "$CONTENTS/Resources/QuotaBar.icns"

SIGN_IDENTITY="${QUOTABAR_CODESIGN_IDENTITY:--}"
SIGN_ARGUMENTS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGUMENTS+=(--timestamp)
fi

codesign "${SIGN_ARGUMENTS[@]}" \
    --identifier com.patrickradulescu.QuotaBar.AgyBridge \
    "$CONTENTS/Helpers/QuotaBarAgyBridge"
codesign "${SIGN_ARGUMENTS[@]}" --identifier com.patrickradulescu.QuotaBar "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
file "$CONTENTS/MacOS/QuotaBar"
file "$CONTENTS/Helpers/QuotaBarAgyBridge"

echo "$APP"
