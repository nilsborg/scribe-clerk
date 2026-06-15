#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_PNG="$ROOT/Resources/AppIcon.png"
ICONSET="$ROOT/Resources/AppIcon.iconset"
OUTPUT_ICNS="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE_PNG" ]]; then
  echo "Error: Place a 1024×1024 PNG at Resources/AppIcon.png" >&2
  exit 1
fi

WORK_PNG="$ROOT/Resources/.AppIcon-work.png"
sips -s format png "$SOURCE_PNG" --out "$WORK_PNG" >/dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -s format png -z 16 16 "$WORK_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -s format png -z 32 32 "$WORK_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32 "$WORK_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -s format png -z 64 64 "$WORK_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128 "$WORK_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -s format png -z 256 256 "$WORK_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256 "$WORK_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -s format png -z 512 512 "$WORK_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512 "$WORK_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$WORK_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"
rm -rf "$ICONSET" "$WORK_PNG"

echo "Generated $OUTPUT_ICNS"
