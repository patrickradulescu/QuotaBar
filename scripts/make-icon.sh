#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/Assets/AppIcon.svg"
OUTPUT="${1:-$ROOT/.build/QuotaBar.icns}"
ICONSET="$(mktemp -d /tmp/quotabar-icon.XXXXXX)/QuotaBar.iconset"

cleanup() {
  rm -rf "${ICONSET:h}"
}
trap cleanup EXIT

mkdir -p "$ICONSET" "${OUTPUT:h}"

render() {
  local pixels="$1"
  local filename="$2"
  /opt/homebrew/bin/magick -background none "$SOURCE" -resize "${pixels}x${pixels}" "$ICONSET/$filename"
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT"
