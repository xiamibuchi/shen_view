#!/bin/bash
set -euo pipefail

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/../paths.sh"

app="$viewer_root/build/macos/Build/Products/Release/ShenView.app"
version=$(awk '/^version: / { print $2 }' "$viewer_root/pubspec.yaml")
if [[ ! "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+[+][0-9]+$ ]]; then
  echo "Invalid Flutter release version: $version" >&2
  exit 1
fi
release_version=${version/+/.}
output="$repository_root/artifacts/releases/$release_version/macos-arm64/zip-ci"
archive="ShenView-$release_version-macos-arm64-ci.zip"

verify_app() {
  local bundle=$1
  local executable="$bundle/Contents/MacOS/ShenView"
  test -x "$executable"
  test "$(plutil -extract LSMinimumSystemVersion raw -o - "$bundle/Contents/Info.plist")" = 15.0
  test "$(lipo -archs "$executable")" = arm64
  vtool -show-build "$executable" | grep -Eq 'minos 15[.]0'
  codesign --verify --deep --strict "$bundle"
  python3 - "$bundle" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

app = Path(sys.argv[1])
root = app / 'Contents/MacOS/codecs'
manifest = json.loads((app / 'Contents/Resources/codecs/manifest.json').read_text())
files = manifest['files']
required = {
    'ffmpeg/ffmpeg', 'ffmpeg/ffprobe', 'imagemagick/magick',
    'imagemagick/modules/coders/info.so',
    'imagemagick/modules/coders/jpeg.so',
    'imagemagick/modules/coders/rgb.so',
}
listed = {entry['path'] for entry in files}
if not required <= listed:
    raise SystemExit(f'Missing bundled codecs: {sorted(required - listed)}')
for entry in files:
    binary = root / entry['path']
    if not binary.is_file() or hashlib.sha256(binary.read_bytes()).hexdigest() != entry['sha256']:
        raise SystemExit(f'Bundled codec hash mismatch: {binary}')
    if entry['archs'] != ['arm64']:
        raise SystemExit(f'Unexpected codec architecture: {binary}')
    if tuple(map(int, entry['minimumMacOS'].split('.'))) > (15, 0):
        raise SystemExit(f'Codec requires a newer macOS: {binary}')
print(f'Verified {len(files)} bundled codec binaries and libraries')
PY
}

verify_app "$app"
mkdir -p "$output"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$archive"
extract_dir=$(mktemp -d)
trap 'rm -rf -- "$extract_dir"' EXIT
ditto -x -k "$output/$archive" "$extract_dir"
verify_app "$extract_dir/ShenView.app"

(cd "$output" && shasum -a 256 "$archive" > SHA256SUMS.txt)
source_sha=$(git -C "$repository_root" rev-parse HEAD)
archive_sha=$(awk '{ print $1 }' "$output/SHA256SUMS.txt")
python3 - "$version" "$source_sha" "$archive" "$archive_sha" > "$output/release.json" <<'PY'
import json
import sys

version, source_sha, archive, archive_sha = sys.argv[1:]
print(json.dumps({
    'version': version,
    'sourceSha': source_sha,
    'platform': 'macos-arm64',
    'minimumMacOS': '15.0',
    'archive': archive,
    'sha256': archive_sha,
    'signing': 'ad-hoc CI preview',
}, indent=2))
PY
echo "Packaged $output/$archive"
