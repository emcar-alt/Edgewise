#!/bin/bash
# Regenerates PrivateAPI/UniversalControl.tbd from the symbols edgewisectl actually uses.
# Pass object files from both optimized and unoptimized builds; they reference slightly
# different symbols (e.g. type descriptors the optimizer specializes on).
#
#   scripts/gen-tbd.sh edgewisectl-O.o edgewisectl-Onone.o
#
# The .tbd is a link-time stub only: at runtime dyld binds to the real
# /System/Library/PrivateFrameworks/UniversalControl.framework. Each symbol is checked
# against the framework's export trie on this Mac so a typo fails here, not at launch.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/PrivateAPI/UniversalControl.tbd"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

clang -O1 -o "$work/exports" "$root/scripts/exports.c"
"$work/exports" > "$work/available.txt"

{ for o in "$@"; do nm -u "$o"; done; } | grep "UniversalControl" | sort -u > "$work/needed.txt"
missing=$(comm -23 "$work/needed.txt" <(sort -u "$work/available.txt") || true)
if [[ -n "$missing" ]]; then
  echo "These symbols are not exported by UniversalControl.framework on this Mac:" >&2
  echo "$missing" >&2
  exit 1
fi

{
  echo "--- !tapi-tbd"
  echo "tbd-version:     4"
  echo "targets:         [ arm64-macos, arm64e-macos, x86_64-macos ]"
  echo "install-name:    '/System/Library/PrivateFrameworks/UniversalControl.framework/Versions/A/UniversalControl'"
  echo "exports:"
  echo "  - targets:         [ arm64-macos, arm64e-macos, x86_64-macos ]"
  echo "    symbols:         ["
  sed "s/.*/                       '&',/" "$work/needed.txt" | sed '$ s/,$//'
  echo "                     ]"
  echo "..."
} > "$out"

echo "wrote $out ($(wc -l < "$work/needed.txt" | tr -d ' ') symbols)"
