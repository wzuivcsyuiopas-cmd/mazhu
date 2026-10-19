#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BUILD="${TUMA_BUILD_DIR:-$TASK_ROOT/.build-local}"
TASK_APP="${TUMA_APP_PATH:-$TASK_ROOT/dist/码住.app}"
mkdir -p "$TASK_BUILD" "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" "$TASK_ROOT"/Sources/TuMa/*.swift -o "$TASK_BUILD/TuMa"
cp "$TASK_BUILD/TuMa" "$TASK_APP/Contents/MacOS/TuMa"
cp "$TASK_ROOT/Info.plist" "$TASK_APP/Contents/Info.plist"
if [[ -f "$TASK_ROOT/AppIcon.icns" ]]; then cp "$TASK_ROOT/AppIcon.icns" "$TASK_APP/Contents/Resources/AppIcon.icns"; fi
for TASK_NOTICE in LICENSE NOTICE.md; do
  if [[ -f "$TASK_ROOT/$TASK_NOTICE" ]]; then cp "$TASK_ROOT/$TASK_NOTICE" "$TASK_APP/Contents/Resources/$TASK_NOTICE"; fi
done
codesign --force --sign - "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
echo "$TASK_APP"
