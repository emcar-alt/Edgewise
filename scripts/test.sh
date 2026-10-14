#!/bin/bash
# Builds and runs the unit tests (pointer-push logic) without Xcode.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build"
swiftc -swift-version 5 -parse-as-library -module-name EdgewiseTests \
  "$root/Sources/Edgewise/EdgePush.swift" "$root/Sources/Edgewise/Displays.swift" "$root/Tests/PushAccumulatorTests.swift" \
  -o "$root/build/EdgewiseTests"
"$root/build/EdgewiseTests"
