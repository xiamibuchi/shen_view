#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/../paths.sh"
root="$repository_root"
archs=$(printf '%s' "${ARCHS:-$(uname -m)}" | tr ' ' ',')
cd "$viewer_root"
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" tool/install_svg_codecs.dart --output "$root/build/svg-codecs" --arch "$archs"
destination="$1/Contents/MacOS/codecs"
mkdir -p "$destination/licenses/resvg"
cp "$root/build/svg-codecs/bin/resvg" "$destination/resvg"
cp "$root/build/svg-codecs/licenses/resvg/"* "$destination/licenses/resvg/"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] || [ -z "$identity" ]; then identity=-; fi
codesign --force --sign "$identity" --entitlements "$root/native/svg_codec/macos.entitlements" "$destination/resvg"
