#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_ROOT/Info.plist")"
[[ "$TASK_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid app version'; exit 1; }
"$TASK_ROOT/scripts/check.sh"
"$TASK_ROOT/scripts/build.sh"
TASK_STAGE="$(mktemp -d)"
TASK_MOUNT="$(mktemp -d)"
trap 'hdiutil detach "$TASK_MOUNT" >/dev/null 2>&1 || true; rm -rf "$TASK_STAGE" "$TASK_MOUNT"' EXIT
ditto "$TASK_ROOT/dist/码住.app" "$TASK_STAGE/码住.app"
ln -s /Applications "$TASK_STAGE/Applications"
mkdir -p "$TASK_ROOT/release"
TASK_DMG="$TASK_ROOT/release/Mazhu-$TASK_VERSION-macOS-arm64.dmg"
hdiutil create -volname '码住' -srcfolder "$TASK_STAGE" -format UDZO -ov "$TASK_DMG"
hdiutil verify "$TASK_DMG"
hdiutil attach -readonly -nobrowse -mountpoint "$TASK_MOUNT" "$TASK_DMG"
codesign --verify --deep --strict "$TASK_MOUNT/码住.app"
lipo -verify_arch arm64 "$TASK_MOUNT/码住.app/Contents/MacOS/TuMa"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_MOUNT/码住.app/Contents/Info.plist")" == "$TASK_VERSION" ]]
[[ "$(readlink "$TASK_MOUNT/Applications")" == /Applications ]]
print "$TASK_DMG"
