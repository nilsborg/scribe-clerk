#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Voice Memo Transcriber"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"
INFO_PLIST="$ROOT/Resources/Info.plist"

cd "$ROOT"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/VoiceMemoTranscriber" "$APP_DIR/Contents/MacOS/VoiceMemoTranscriber"
ICON_SRC="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$ICON_SRC" ]]; then
  echo "Error: App icon not found at $ICON_SRC" >&2
  exit 1
fi

cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

echo "Built $APP_DIR"
