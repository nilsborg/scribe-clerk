#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PNG="$ROOT/Resources/AppIcon.png"
ICONSET="$ROOT/Resources/AppIcon.iconset"
ASSET_ICONSET="$ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
OUTPUT_ICNS="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "Error: Place a 1024×1024 PNG at Resources/AppIcon.png" >&2
  exit 1
fi

WORK_PNG="$ROOT/Resources/.AppIcon-work.png"
sips -s format png "$SOURCE_PNG" --out "$WORK_PNG" >/dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET" "$ASSET_ICONSET"

write_icon() {
  local size="$1"
  local name="$2"
  sips -s format png -z "$size" "$size" "$WORK_PNG" --out "$ICONSET/$name" >/dev/null
  cp "$ICONSET/$name" "$ASSET_ICONSET/$name"
}

write_icon 16 icon_16x16.png
write_icon 32 icon_16x16@2x.png
write_icon 32 icon_32x32.png
write_icon 64 icon_32x32@2x.png
write_icon 128 icon_128x128.png
write_icon 256 icon_128x128@2x.png
write_icon 256 icon_256x256.png
write_icon 512 icon_256x256@2x.png
write_icon 512 icon_512x512.png
write_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"
rm -rf "$ICONSET" "$WORK_PNG"

echo "Generated $OUTPUT_ICNS and $ASSET_ICONSET"
