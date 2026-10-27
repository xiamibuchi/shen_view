#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[[ $# == 0 ]] || fail 'Usage: bash tool/check/staged_files.sh'
root=$(git rev-parse --show-toplevel)
cd "$root"
gitdir=$(git rev-parse --absolute-git-dir)
gitdir=$(cd "$gitdir" && pwd -P)
scratch=$(mktemp -d "$gitdir/staged-files.XXXXXX")
case "$scratch" in "$gitdir"/staged-files.*) ;; *) exit 1 ;; esac
[[ ! -L "$scratch" ]] || exit 1
trap 'rm -rf -- "$scratch"' EXIT

limit_mib=20
limit_bytes=$((limit_mib * 1024 * 1024))
lfs_checked=0
count=0
lfs_count=0
errors=0

git diff --cached --no-ext-diff --no-renames --name-only --diff-filter=ACMRT -z > "$scratch/paths"
git diff --cached --no-ext-diff --no-renames --name-only -z > "$scratch/changes"
while IFS= read -r -d '' path; do
    if [[ ${path##*/} == .gitattributes ]]; then
        # New attributes can require conversion of otherwise unchanged files.
        git ls-files -z > "$scratch/all-paths"
        mv "$scratch/all-paths" "$scratch/paths"
        break
    fi
done < "$scratch/changes"
while IFS= read -r -d '' path; do
    git --literal-pathspecs ls-files --stage -z -- "$path" > "$scratch/entry"
    IFS= read -r -d '' entry < "$scratch/entry"
    IFS=' ' read -r mode oid stage <<< "${entry%%$'\t'*}"
    [[ $stage == 0 ]] || fail "Unmerged index entry: $path"
    case "$mode" in 100644|100755) ;; *) continue ;; esac
    size=$(git cat-file -s "$oid")
    git check-attr --cached -z filter -- "$path" > "$scratch/attribute"
    {
        IFS= read -r -d '' attr_path
        IFS= read -r -d '' attr_name
        IFS= read -r -d '' filter
    } < "$scratch/attribute"
    count=$((count + 1))
    if [[ $filter == lfs ]]; then
        if [[ $lfs_checked == 0 ]]; then
            git lfs version >/dev/null 2>&1 || fail 'Git LFS is required. Install it, then run: git lfs install --local --skip-repo'
            required=$(git config --bool --get filter.lfs.required || :)
            process=$(git config --get filter.lfs.process || :)
            clean=$(git config --get filter.lfs.clean || :)
            smudge=$(git config --get filter.lfs.smudge || :)
            if [[ $required != true || ( -z $process && ( -z $clean || -z $smudge ) ) ]]; then
                fail 'Git LFS filters are not configured. Run: git lfs install --local --skip-repo'
            fi
            lfs_checked=1
        fi
        # Git LFS represents empty files as empty Git blobs, not pointers.
        if [[ $size == 0 ]]; then
            lfs_count=$((lfs_count + 1))
            continue
        fi
        valid=0
        if ((size <= 1024)); then
            git cat-file blob "$oid" > "$scratch/pointer"
            if git lfs pointer --check --strict --file="$scratch/pointer" >/dev/null 2>&1; then
                valid=1
            fi
        fi
        if [[ $valid == 0 ]]; then
            printf 'LFS path contains raw data or an invalid pointer: %s (%s staged bytes).\n' "$path" "$size" >&2
            printf '%s\n' 'Run git lfs install --local --skip-repo, then re-add this file with git add --renormalize -- PATH.' >&2
            errors=$((errors + 1))
        else
            lfs_count=$((lfs_count + 1))
        fi
    elif ((size > limit_bytes)); then
        printf 'Ordinary Git file exceeds %s MiB: %s (%s staged bytes).\n' "$limit_mib" "$path" "$size" >&2
        printf '%s\n' 'Reduce the file, or add an appropriate LFS rule and re-add it before committing.' >&2
        errors=$((errors + 1))
    fi
done < "$scratch/paths"

((errors == 0)) || fail "FAIL: $errors staged file violation(s)."
printf 'PASS: %s staged file(s), %s LFS file(s).\n' "$count" "$lfs_count"
