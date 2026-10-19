#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BUILD="${TUMA_BUILD_DIR:-$TASK_ROOT/.build-local}"
mkdir -p "$TASK_BUILD"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos26.0 -sdk "$(xcrun --show-sdk-path)" "$TASK_ROOT/Sources/TuMa/ImageEngine.swift" "$TASK_ROOT/Sources/TuMa/WorkspaceModel.swift" "$TASK_ROOT/Sources/TuMa/CanvasView.swift" "$TASK_ROOT/Sources/TuMa/ToolPicker.swift" "$TASK_ROOT/Sources/TuMa/WindowBehavior.swift" "$TASK_ROOT/Sources/TuMa/PhotoRow.swift" "$TASK_ROOT/Sources/TuMa/PhotoSidebar.swift" "$TASK_ROOT/Tests/CoreChecks.swift" -o "$TASK_BUILD/CoreChecks"
"$TASK_BUILD/CoreChecks"
