#!/bin/sh
set -eu
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/../paths.sh"
root="$repository_root"
architectures=$(printf '%s' "${ARCHS:-$(uname -m)}" | tr ' ' ';')
cmake -S "$root/native/hdr_codecs" -B "$root/build/avif-codecs" \
  -DSHENVIEW_AVIF_ONLY=ON -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_OSX_ARCHITECTURES=$architectures" \
  "-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.0}"
cmake --build "$root/build/avif-codecs" --config Release --target viewer_avif_animation --parallel 2
destination="$1/Contents/MacOS/codecs"
mkdir -p "$destination/licenses/hdr"
cp "$root/build/avif-codecs/bin/viewer_avif_animation" "$destination/"
cp "$root/build/avif-codecs/licenses/hdr/"* "$destination/licenses/hdr/"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] || [ -z "$identity" ]; then identity=-; fi
codesign --force --sign "$identity" --entitlements "$root/native/svg_codec/macos.entitlements" "$destination/viewer_avif_animation"
