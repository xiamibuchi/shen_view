#!/bin/sh
set -eu
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/../paths.sh"
root="$repository_root"
architectures=$(printf '%s' "${ARCHS:-$(uname -m)}" | tr ' ' ';')
cmake -S "$root/native/archive_helper" -B "$root/build/archive-helper" \
  -DCMAKE_BUILD_TYPE=Release "-DCMAKE_OSX_ARCHITECTURES=$architectures" \
  "-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-11.0}"
cmake --build "$root/build/archive-helper" --config Release --parallel 2
if [ "${1:-}" != "" ]; then
  # Pass e.g. build/macos/Build/Products/Release/ShenView.app.
  destination="$1/Contents/MacOS/codecs"
  mkdir -p "$destination/licenses/7zip"
  cp "$root/build/archive-helper/bin/viewer_archive" "$root/build/archive-helper/bin/7z.so" "$destination/"
  cp "$root/build/archive-helper/licenses/7zip/"* "$destination/licenses/7zip/"
  identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] || [ -z "$identity" ]; then identity=-; fi
  # Embedded executables inherit the app sandbox and must share its identity.
  codesign --force --sign "$identity" "$destination/7z.so"
  codesign --force --sign "$identity" \
    --entitlements "$root/native/archive_helper/macos.entitlements" \
    "$destination/viewer_archive"
fi
