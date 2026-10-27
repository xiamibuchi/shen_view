#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd -P)
mkdir -p "$root/artifacts"
work=$(mktemp -d "$root/artifacts/staged-tests.XXXXXX")
case "$work" in "$root"/artifacts/staged-tests.*) ;; *) exit 1 ;; esac
[[ ! -L "$work" ]] || exit 1
trap 'cd "$root"; rm -rf -- "$work"' EXIT
unicode=$(printf '\346\265\213')
count=0

init_repo() {
    mkdir -p "$1/tool/check" "$1/.githooks"
    cp "$root/.gitattributes" "$1/.gitattributes"
    cp "$root/.githooks/"* "$1/.githooks/"
    cp "$root/tool/check/staged_files.sh" "$root/tool/check/commit_message.sh" "$1/tool/check/"
    chmod +x "$1/.githooks/"*
    git -C "$1" init -q -b main
    git -C "$1" config user.name 'Staged Files Test'
    git -C "$1" config user.email 'staged-test@example.invalid'
    git -C "$1" config commit.gpgsign false
    git -C "$1" config core.autocrlf false
    git -C "$1" config core.hooksPath .githooks
    git -C "$1" lfs install --local --skip-repo >/dev/null
}

assert_check() {
    if bash tool/check/staged_files.sh > "$work/output" 2>&1; then actual=0; else actual=$?; fi
    if [[ $actual != "$1" ]]; then
        cat "$work/output" >&2
        printf 'Expected exit %s, got %s\n' "$1" "$actual" >&2
        exit 1
    fi
    count=$((count + 1))
}

repo="$work/repo space $unicode"
init_repo "$repo"
cd "$repo"
git add .gitattributes
git commit -qm 'test: initial file policy' > "$work/output" 2>&1
assert_check 0
dd if=/dev/zero of=ordinary.bin bs=1048576 count=20 2>/dev/null
git add ordinary.bin
assert_check 0
printf x >> ordinary.bin
assert_check 0
git add ordinary.bin
assert_check 1
printf small > ordinary.bin
assert_check 1
before=$(git rev-parse HEAD)
if git commit -qm 'test: oversized ordinary asset' > "$work/output" 2>&1; then
    printf '%s\n' 'Pre-commit accepted an oversized file.' >&2
    exit 1
fi
[[ $(git rev-parse HEAD) == "$before" ]] || exit 1
count=$((count + 1))
printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > .gitattributes
assert_check 1
cp "$root/.gitattributes" .gitattributes
blob=$(git rev-parse :ordinary.bin)
legacy=$(git commit-tree "$(git write-tree)" -p HEAD -m 'test: legacy oversized asset')
git update-ref HEAD "$legacy"
git rm -q .gitattributes
assert_check 1
git checkout HEAD -- .gitattributes
git cat-file blob "$blob" > ordinary.bin
git mv ordinary.bin "renamed space $unicode.bin"
assert_check 1
git rm -qf -- "renamed space $unicode.bin"
assert_check 0
git commit -qm 'test: delete legacy asset' > "$work/output" 2>&1
printf small > '[asset].bin'
git --literal-pathspecs add -- '[asset].bin'
assert_check 0
git reset -q HEAD -- .

mkdir -p apps/viewer/testdata
file="apps/viewer/testdata/large space $unicode.bin"
dd if=/dev/zero of="$file" bs=1048576 count=21 2>/dev/null
git add -- "$file"
assert_check 0
printf changed > "$file"
assert_check 0
git config --local filter.lfs.required false
assert_check 1
git config --local filter.lfs.required true
raw=$(printf 'raw payload' | git hash-object -w --stdin)
git update-index --add --cacheinfo 100644 "$raw" "$file"
assert_check 1
printf '*.bin -filter\n' > .gitattributes
assert_check 1
cp "$root/.gitattributes" .gitattributes
bad=$(printf 'version https://git-lfs.github.com/spec/v1\noid sha256:bad\nsize 5\n' | git hash-object -w --stdin)
git update-index --add --cacheinfo 100644 "$bad" "$file"
assert_check 1
printf 'small LFS payload' > "$file"
git add --renormalize -- "$file"
assert_check 0
: > apps/viewer/testdata/empty.bin
git add apps/viewer/testdata/empty.bin
assert_check 0
printf '<svg/>\r\n' > apps/viewer/testdata/example.svg
printf '{"value":1}\r\n' > apps/viewer/testdata/example.json
printf 'license\r\n' > apps/viewer/testdata/LICENSE.txt
printf '# Test\n' > apps/viewer/testdata/README.md
git add apps/viewer/testdata/example.svg apps/viewer/testdata/example.json apps/viewer/testdata/LICENSE.txt apps/viewer/testdata/README.md
assert_check 0
for text in example.svg example.json LICENSE.txt; do
    [[ $(git hash-object --no-filters -- "apps/viewer/testdata/$text") == $(git rev-parse ":apps/viewer/testdata/$text") ]] || exit 1
    count=$((count + 1))
done
link=$(printf 'example.svg' | git hash-object -w --stdin)
git update-index --add --cacheinfo 120000 "$link" apps/viewer/testdata/link.png
assert_check 0
git update-index --force-remove apps/viewer/testdata/link.png
git update-index --add --cacheinfo 160000 "$(git rev-parse HEAD)" submodule
assert_check 0
git update-index --force-remove submodule
git reset -q HEAD -- .
mkdir -p extra
printf 'legacy payload' > extra/legacy.bin
git add extra/legacy.bin
git commit -qm 'test: existing ordinary asset' > "$work/output" 2>&1
printf 'extra/** filter=lfs diff=lfs merge=lfs -text\n' >> .gitattributes
git add .gitattributes
assert_check 1
git add --renormalize -- extra/legacy.bin
assert_check 0

# Upload and re-check out the actual fixture set against a local LFS remote.
fixture_repo="$work/fixture repo $unicode"
init_repo "$fixture_repo"
cd "$root"
git ls-files -z -- apps/viewer/testdata > "$work/fixtures"
while IFS= read -r -d '' path; do
    mkdir -p "$fixture_repo/$(dirname "$path")"
    cp "$root/$path" "$fixture_repo/$path"
done < "$work/fixtures"
cd "$fixture_repo"
git add .gitattributes apps/viewer/testdata
assert_check 0
git commit -qm 'test: fixture round trip' > "$work/output" 2>&1
git init -q --bare -b main "$work/remote.git"
git remote add origin "$work/remote.git"
git push -q origin main > "$work/upload" 2>&1 || { cat "$work/upload" >&2; exit 1; }
GIT_LFS_SKIP_SMUDGE=1 git clone -q --branch main "$work/remote.git" "$work/clone space $unicode"
git -C "$work/clone space $unicode" lfs install --local --skip-repo >/dev/null
git -C "$work/clone space $unicode" lfs pull > "$work/download" 2>&1 || { cat "$work/download" >&2; exit 1; }
fixtures=0
while IFS= read -r -d '' path; do
    case "$path" in *.md) continue ;; esac
    cmp "$root/$path" "$work/clone space $unicode/$path"
    fixtures=$((fixtures + 1))
done < "$work/fixtures"
count=$((count + 1))
printf 'PASS: %s staged-file checks; %s fixture files round-tripped byte-for-byte.\n' "$count" "$fixtures"
