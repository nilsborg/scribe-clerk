#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

XCODE_APP=""
for candidate in \
  "/Applications/Xcode.app" \
  "$HOME/Applications/Xcode.app"; do
  if [[ -d "$candidate" ]]; then
    XCODE_APP="$candidate"
    break
  fi
done

if [[ -z "$XCODE_APP" ]]; then
  XCODE_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -1)"
fi

if [[ -z "$XCODE_APP" || ! -d "$XCODE_APP" ]]; then
  echo "Xcode.app not found." >&2
  echo "Install Xcode from the App Store, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

ACTIVE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$ACTIVE_DEV_DIR" == *"CommandLineTools"* ]]; then
  echo "Note: command line tools are active, not full Xcode."
  echo "For ⌘R builds inside Xcode to work reliably, run once:"
  echo "  sudo xcode-select -s $XCODE_APP/Contents/Developer"
  echo ""
fi

open -a "$XCODE_APP" "$ROOT/Package.swift"
echo "Opened in Xcode. Press ⌘R to build and run."
