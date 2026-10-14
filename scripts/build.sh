#!/bin/bash
# Builds build/Edgewise.app with nothing but the Xcode Command Line Tools.
#
#   scripts/build.sh            # release build for this Mac's architecture
#   ARCHS="arm64 x86_64" scripts/build.sh   # universal
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build"
app="$build/Edgewise.app"
version="${VERSION:-$(cat "$root/VERSION")}"
build_number="${BUILD_NUMBER:-$(git -C "$root" rev-list --count HEAD 2>/dev/null || echo 1)}"
archs="${ARCHS:-$(uname -m)}"
min_macos="13.0"
swift_flags=(-O -swift-version 5)

rm -rf "$app"
mkdir -p "$build/modules" "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"

binaries_app=()
binaries_ctl=()
for arch in $archs; do
  target="$arch-apple-macos$min_macos"
  modules="$build/modules/$arch"
  mkdir -p "$modules"

  # Interface-only module for the private framework (never linked; see PrivateAPI/).
  swiftc -parse-as-library -emit-module -enable-library-evolution -module-name UniversalControl \
    -target "$target" "$root/PrivateAPI/UniversalControl/UniversalControl.swift" \
    -emit-module-path "$modules/UniversalControl.swiftmodule"

  swiftc "${swift_flags[@]}" -target "$target" -I "$modules" -module-name edgewisectl \
    "$root/Sources/edgewisectl/main.swift" "$root/PrivateAPI/UniversalControl.tbd" \
    -o "$build/edgewisectl-$arch"
  binaries_ctl+=("$build/edgewisectl-$arch")

  swiftc "${swift_flags[@]}" -target "$target" -parse-as-library -module-name Edgewise \
    "$root"/Sources/Edgewise/*.swift -o "$build/Edgewise-$arch"
  binaries_app+=("$build/Edgewise-$arch")
done

lipo -create "${binaries_app[@]}" -output "$app/Contents/MacOS/Edgewise"
lipo -create "${binaries_ctl[@]}" -output "$app/Contents/Helpers/edgewisectl"

sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build_number/" "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$app/Contents/PkgInfo"

# Ad-hoc signature (no Apple Developer ID needed). Sign the helper first, then the bundle.
codesign --force --options runtime --timestamp=none --sign - "$app/Contents/Helpers/edgewisectl"
codesign --force --options runtime --timestamp=none --sign - "$app"

echo "built $app ($version, $archs)"
