#!/usr/bin/env bash
set -euo pipefail
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/profile.sh"
root=$(cygpath -u "$SHENVIEW_FFMPEG_BUILD_ROOT")
source_root=$(cygpath -u "$SHENVIEW_FFMPEG_SOURCE")
compiler_root=$(cygpath -u "$SHENVIEW_FFMPEG_COMPILER")
for codec_patch in "$script_directory"/patches/*.patch; do
  if ! patch --batch --dry-run --reverse --silent -d "$source_root" -p1 < "$codec_patch" >/dev/null 2>&1; then
    patch --batch -d "$source_root" -p1 < "$codec_patch"
  fi
done
export PATH="$root/sysroot/usr/bin:$root/sysroot/mingw64/bin:$compiler_root:$PATH"
export PKG_CONFIG_LIBDIR="$SHENVIEW_FFMPEG_BUILD_ROOT/sysroot/mingw64/lib/pkgconfig"
mkdir -p "$root/build"
cd "$root/build"
"$source_root/configure" "${ffmpeg_profile[@]}" \
  "--prefix=$SHENVIEW_FFMPEG_BUILD_ROOT/install" \
  --target-os=mingw32 --arch=x86_64 --cc=gcc --cxx=g++ \
  --disable-schannel --disable-d3d11va --disable-d3d12va --disable-dxva2
make -j8
make install
