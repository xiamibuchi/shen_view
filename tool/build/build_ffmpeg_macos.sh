#!/bin/bash
set -euo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/../paths.sh"
. "$repository_root/third_party/ffmpeg/profile.sh"

work="$native_build_root/ffmpeg/macos"
source_archive="$work/ffmpeg-9.0.2.tar.xz"
source_directory="$work/source/ffmpeg-9.0.2"
build_directory="$work/build"
install_directory="$work/install"
mkdir -p "$work" "$work/source" "$build_directory"

expected_hash=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"].lower())' \
  "$repository_root/third_party/ffmpeg/source.lock.json")
if [ ! -f "$source_archive" ]; then
  curl -fL --retry 3 -o "$source_archive.part" \
    'https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz'
  mv "$source_archive.part" "$source_archive"
fi
actual_hash=$(shasum -a 256 "$source_archive" | awk '{print $1}')
if [ "$actual_hash" != "$expected_hash" ]; then
  echo 'FFmpeg source SHA256 does not match source.lock.json' >&2
  exit 1
fi
if [ ! -f "$source_directory/configure" ]; then
  tar -xf "$source_archive" -C "$work/source"
fi

export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:/opt/homebrew/share/pkgconfig:/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
pkg-config --exists dav1d zimg libplacebo vulkan || {
  echo 'FFmpeg build needs dav1d, zimg, libplacebo and vulkan pkg-config packages' >&2
  exit 1
}
host_arch=$(uname -m)
requested_archs=" ${ARCHS:-$host_arch} "
case "$requested_archs" in
  *" $host_arch "*) ;;
  *) echo "FFmpeg build host $host_arch is not in ARCHS=$requested_archs" >&2; exit 1 ;;
esac

identity=$(printf '%s\n' "$expected_hash" "$host_arch" "${MACOSX_DEPLOYMENT_TARGET:-15.0}" \
  "$(shasum -a 256 "$repository_root/third_party/ffmpeg/profile.sh" | awk '{print $1}')" \
  "$(pkg-config --modversion dav1d zimg libplacebo vulkan)" | shasum -a 256 | awk '{print $1}')
if [ ! -f "$work/build-identity" ] || [ "$(cat "$work/build-identity")" != "$identity" ] || \
   [ ! -x "$install_directory/bin/ffmpeg" ] || [ ! -x "$install_directory/bin/ffprobe" ]; then
  cd "$build_directory"
  if [ -f Makefile ]; then make distclean >/dev/null; fi
  export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
  "$source_directory/configure" --prefix="$install_directory" \
    "${ffmpeg_profile[@]}" --enable-pic --cc=clang \
    --extra-cflags="-I$(brew --prefix)/include" \
    --extra-ldflags="-L$(brew --prefix)/lib"
  make -j "${SHENVIEW_BUILD_JOBS:-4}"
  make install
  printf '%s' "$identity" > "$work/build-identity"
fi

"$install_directory/bin/ffmpeg" -hide_banner -filters | grep -q ' zscale '
"$install_directory/bin/ffmpeg" -hide_banner -filters | grep -q ' libplacebo '
"$install_directory/bin/ffprobe" -version >/dev/null
