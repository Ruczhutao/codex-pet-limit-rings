#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/tmp/CodexPetLimitRings.app"
DMG="$ROOT/CodexPetLimitRings.dmg"
VOLNAME="CodexPetLimitRings"
TMPDIR="$ROOT/tmp/dmg-staging"

# Build app first if not exists
if [ ! -d "$APP" ]; then
    bash "$ROOT/tools/build-limit-rings.sh"
fi

# Clean up
rm -rf "$TMPDIR" "$DMG"
mkdir -p "$TMPDIR"

# Copy app and create Applications alias
cp -R "$APP" "$TMPDIR/"
ln -s /Applications "$TMPDIR/Applications"

# Create uncompressed DMG
TMPDMG="$ROOT/tmp/tmp.dmg"
hdiutil create -volname "$VOLNAME" -srcfolder "$TMPDIR" -ov -format UDRW "$TMPDMG"

# Mount it to set window properties
MOUNTPOINT="/Volumes/$VOLNAME"
hdiutil attach "$TMPDMG" -nobrowse >/dev/null

# Wait for mount
sleep 1

# Use AppleScript to set window appearance
osascript <<EOF
tell application "Finder"
    set dmg to disk "$VOLNAME"
    open dmg
    set toolbar visible of front window to false
    set statusbar visible of front window to false
    set bounds of front window to {100, 100, 500, 400}
    set current view of front window to icon view
    set icon size of icon view options of front window to 128
    set text size of icon view options of front window to 14
    set arrangement of icon view options of front window to not arranged
    set position of item "CodexPetLimitRings" of dmg to {120, 150}
    set position of item "Applications" of dmg to {280, 150}
    close front window
end tell
EOF

# Unmount
hdiutil detach "$MOUNTPOINT" -force >/dev/null || true
sleep 1

# Convert to compressed DMG
hdiutil convert "$TMPDMG" -format UDZO -o "$DMG"
rm -f "$TMPDMG"
rm -rf "$TMPDIR"

echo "$DMG"
