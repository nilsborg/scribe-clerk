#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v fswatch >/dev/null; then
  echo "fswatch is required for auto-rebuild on save."
  echo "Install it with: brew install fswatch"
  exit 1
fi

echo "Watching Sources/ and Package.swift — saving a file rebuilds the app."
echo "Press Ctrl+C to stop."
echo ""

./scripts/build-app.sh

fswatch -o Sources Package.swift scripts/build-app.sh | while read -r _; do
  echo ""
  echo "── Change detected at $(date +%H:%M:%S) ──"
  if ./scripts/build-app.sh; then
    echo "✓ Rebuilt dist/Voice Memo Transcriber.app"
  else
    echo "✗ Build failed"
  fi
done
