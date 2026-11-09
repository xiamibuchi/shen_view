#!/bin/sh
set -eu
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/../paths.sh"

if [ "${CONFIGURATION:-Release}" != "Release" ]; then exit 0; fi
app=$1
magick=$(brew --prefix imagemagick-full)
if [ ! -x "$magick/bin/magick" ]; then
  echo 'imagemagick-full is required to bundle macOS compatibility decoding' >&2
  exit 1
fi
for arch in ${ARCHS:-$(uname -m)}; do
  if ! lipo -archs "$magick/bin/magick" | grep -qw "$arch"; then
    echo "ImageMagick has no $arch slice; macOS bundle cannot support that architecture" >&2
    exit 1
  fi
done

/bin/bash "$script_directory/build_ffmpeg_macos.sh"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ] || [ -z "$identity" ]; then identity=-; fi
python3 "$script_directory/bundle_macos_codecs.py" \
  --app "$app" --ffmpeg "$native_build_root/ffmpeg/macos" \
  --imagemagick "$magick" --archs ${ARCHS:-$(uname -m)} \
  --min-os "${MACOSX_DEPLOYMENT_TARGET:-15.0}" --sign "$identity"
