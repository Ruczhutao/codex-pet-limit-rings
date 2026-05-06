#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/tmp/CodexPetLimitRings.app}"
BIN="$APP/Contents/MacOS/CodexPetLimitRings"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/tools/CodexPetLimitRings-Info.plist" "$APP/Contents/Info.plist"
swiftc "$ROOT/tools/codex-pet-limit-rings.swift" -o "$BIN" -framework AppKit

ICON="$ROOT/resources/icon.png"
if [ -f "$ICON" ]; then
    cp "$ICON" "$APP/Contents/Resources/icon.png"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "$APP"
