#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Scribe Clerk"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/$APP_NAME.app"
INFO_PLIST="$ROOT/Resources/Info.plist"
ASSET_CATALOG="$ROOT/Resources/Assets.xcassets"
ICON_SRC="$ROOT/Resources/AppIcon.icns"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cd "$ROOT"
swift build -c release

if [[ ! -f "$ICON_SRC" ]] || [[ ! -f "$ASSET_CATALOG/AppIcon.appiconset/icon_512x512@2x.png" ]]; then
  bash "$ROOT/scripts/generate-icon.sh"
fi

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/ScribeClerk" "$APP_DIR/Contents/MacOS/ScribeClerk"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

PARTIAL_PLIST="$(mktemp)"
xcrun actool "$ASSET_CATALOG" \
  --compile "$APP_DIR/Contents/Resources" \
  --app-icon AppIcon \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$PARTIAL_PLIST" \
  >/dev/null

if /usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$PARTIAL_PLIST" >/dev/null 2>&1; then
  ICON_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$PARTIAL_PLIST")"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $ICON_NAME" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName $ICON_NAME" "$APP_DIR/Contents/Info.plist"
fi

rm -f "$PARTIAL_PLIST"
touch "$APP_DIR/Contents/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/Assets.car" "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
"$LSREGISTER" -f -R -trusted "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR (CFBundleVersion $BUILD_NUMBER)"
